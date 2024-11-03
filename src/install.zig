const std = @import("std");
const windows = std.os.windows;

// Update Package struct to match your JSON structure
const Package = struct {
    name: []const u8,
    path: []const u8,
    keyword: []const u8,
    description: []const u8,
    global: bool,
};

const PackageFile = struct {
    package: []Package,
};

fn create_portman_directory(arg_root_dir: []const u8) !void {
    // Add null check for empty string case
    if (arg_root_dir.len > 0) {
        std.debug.print("Installing Portman to {s}\n", .{arg_root_dir});
    } else {
        std.debug.print("Installing Portman to current directory\n", .{});
    }
    // Use an arena allocator for all our temporary allocations
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get current executable path
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buffer);
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

    // Convert arg_root_dir to absolute path if provided
    const base_dir = if (arg_root_dir.len > 0) 
        try std.fs.cwd().realpathAlloc(allocator, arg_root_dir)
    else 
        exe_dir;

    // Always create a portman subdirectory
    const root_dir = if (std.mem.eql(u8, std.fs.path.basename(base_dir), "bin"))
        std.fs.path.dirname(base_dir) orelse "."
    else
        try std.fs.path.join(allocator, &[_][]const u8{base_dir, "portman"});

    std.debug.print("Creating directory structure in: {s}\n", .{root_dir});

    // Create root dir if needed
    std.fs.makeDirAbsolute(root_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error creating root dir: {any}\n", .{err});
            return err;
        }
    };

    // Create lib and bin directories
    const lib_path = try std.fs.path.join(allocator, &[_][]const u8{root_dir, "lib"});
    const bin_path = try std.fs.path.join(allocator, &[_][]const u8{root_dir, "bin"});
    
    std.debug.print("Creating lib directory: {s}\n", .{lib_path});
    std.fs.makeDirAbsolute(lib_path) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error creating lib dir: {any}\n", .{err});
            return err;
        }
    };

    std.debug.print("Creating bin directory: {s}\n", .{bin_path});
    std.fs.makeDirAbsolute(bin_path) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error creating bin dir: {any}\n", .{err});
            return err;
        }
    };

    // Create packages.json
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{lib_path, "packages.json"});
    std.debug.print("Creating packages.json: {s}\n", .{packages_path});
    const file = std.fs.createFileAbsolute(packages_path, .{ .exclusive = true }) catch |err| {
        if (err != error.PathAlreadyExists) {
            std.debug.print("Error creating packages.json: {any}\n", .{err});
            return err;
        } else {
            std.debug.print("packages.json already exists\n", .{});
            return;
        }
    };
    defer file.close();

    // Write initial JSON structure
    try file.writeAll(
        \\{
        \\  "package": []
        \\}
        \\
    );

    // Copy executable if needed
    if (!std.mem.eql(u8, std.fs.path.basename(exe_dir), "bin")) {
        const new_exe_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{bin_path, "portman.exe"}
        );
        std.debug.print("Copying executable to: {s}\n", .{new_exe_path});
        try std.fs.copyFileAbsolute(exe_path, new_exe_path, .{});
    }

    std.debug.print("Directory structure verified/created at: {s}\n", .{root_dir});
}

// checks to see if portman is alreadyinstalled
pub fn verify_install() !bool {
    // Use arena allocator instead of page_allocator directly
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buffer);
    const exe_dir = std.fs.path.dirname(exe_path) orelse return error.InvalidPath;
    const parent_dir = std.fs.path.dirname(exe_dir) orelse return error.InvalidPath;
    
    const packages_path = try std.fs.path.join(
        allocator, 
        &[_][]const u8{parent_dir, "lib", "packages.json"}
    );
    
    // Check if both the file exists and is accessible
    const file = std.fs.cwd().openFile(packages_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return false,
            error.AccessDenied => {
                std.debug.print("Warning: Found packages.json but cannot access it\n", .{});
                return false;
            },
            else => return err,
        }
    };
    defer file.close();
    
    return true;
}

pub fn createInstallBat(output_path: []const u8) !void {
    const batch_contents =
        \\@echo off
        \\setlocal enabledelayedexpansion
        \\
        \\REM Get the directory of the batch file
        \\set "portman_path=%~dp0"
        \\if "%portman_path:~-1%"=="\" set "portman_path=%portman_path:~0,-1%"
        \\cd "%portman_path%"
        \\cd ..
        \\set "portman_path=%cd%"
        \\
        \\REM Set PORTMAN_HOME environment variable
        \\setx PORTMAN_HOME "%portman_path%"
        \\
        \\REM Set the paths
        \\set "bin_path=%portman_path%\bin"
        \\
        \\REM Get current PATH from registry
        \\for /f "tokens=2*" %%a in ('reg query "HKEY_CURRENT_USER\Environment" /v PATH') do set "current_path=%%b"
        \\
        \\REM Check if our bin_path is already present
        \\echo !current_path! | findstr /I /C:"%bin_path%" >nul
        \\if errorlevel 1 (
        \\    REM Append to existing PATH (preserving all existing entries)
        \\    setx PATH "!current_path!;%bin_path%"
        \\    echo Added %bin_path% to PATH.
        \\) else (
        \\    echo %bin_path% is already in PATH.
        \\)
        \\
        \\echo.
        \\echo Portman environment setup complete.
        \\echo Please restart your command prompt or terminal for the changes to take effect.
        \\
        \\endlocal
        \\pause
        \\
    ;

    const file = try std.fs.createFileAbsolute(output_path, .{});
    defer file.close();
    try file.writeAll(batch_contents);
}

pub fn install_portman() !void {
    var root_dir: []const u8 = ""; // Default install path
    var force_install = false;
    var skip_path = false;  // New flag for -no-path
    
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get executable path early
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buffer);
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip executable name
    
    // Process arguments
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-f")) {
            force_install = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-no-path")) {
            skip_path = true;
            continue;
        }
        // If we already have a root_dir, this is an unexpected argument
        if (root_dir.len > 0) {
            std.debug.print("Error: Unexpected argument '{s}'\n", .{arg});
            return error.UnexpectedArgument;
        }
        root_dir = arg;
    }
    
    if (root_dir.len == 0) {
        const default_path = try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "portman"});
        // confirms the user intends to install to
        std.debug.print("No install path included. Portman will be installed to: {s}? (Y/n) ", .{default_path});
        
        const stdin = std.io.getStdIn().reader();
        var buf: [2]u8 = undefined;
        const amt = try stdin.read(&buf);
        
        if (amt > 0 and (buf[0] == 'n' or buf[0] == 'N')) {
            std.debug.print("Installation cancelled\n", .{});
            return;
        }
        
        const portman_path = default_path;
        
        if (std.fs.cwd().access(portman_path, .{}) catch null != null) {
            if (force_install) {
                std.debug.print("Force removing existing installation at '{s}'\n", .{portman_path});
                try std.fs.deleteTreeAbsolute(portman_path);
            } else {
                std.debug.print("Error: Directory already contains a 'portman' directory\n", .{});
                return error.PortmanDirectoryExists;
            }
        }
    }

    // Store the actual installation directory
    const installation_dir = if (root_dir.len > 0) 
        try std.fs.path.join(allocator, &[_][]const u8{root_dir, "portman"})  // <-- Fix here
    else 
        try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "portman"});

    std.debug.print("Installing Portman...\n", .{});
    try create_portman_directory(root_dir);

    const install_bat_path = try std.fs.path.join(allocator, &[_][]const u8{installation_dir, "lib", "PATH.bat"});
    try createInstallBat(install_bat_path);

    // Add bin directory to PATH if not skipped
    if (!skip_path) {
        _ = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &[_][]const u8{install_bat_path},
        });
    }

    try install_7zip(allocator);
    std.debug.print("Portman installed successfully!\n", .{});
}

fn copyPackageFiles(allocator: std.mem.Allocator, source_path: []const u8, dest_dir: []const u8) !void {
    // Create the destination directory if it doesn't exist
    try std.fs.cwd().makePath(dest_dir);

    var source_dir = try std.fs.cwd().openDir(source_path, .{ .iterate = true });
    defer source_dir.close();

    var walker = try source_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const source_file_path = try std.fs.path.join(allocator, &[_][]const u8{ source_path, entry.path });
        defer allocator.free(source_file_path);
        
        const dest_file_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_dir, entry.path });
        defer allocator.free(dest_file_path);

        switch (entry.kind) {
            .file => {
                // Create parent directory if needed
                const dest_parent = std.fs.path.dirname(dest_file_path);
                if (dest_parent) |parent| {
                    try std.fs.cwd().makePath(parent);
                }

                // Copy the file
                try std.fs.copyFileAbsolute(source_file_path, dest_file_path, .{});
            },
            .directory => {
                try std.fs.cwd().makePath(dest_file_path);
            },
            else => {},
        }
    }
}

fn install_7zip(allocator: std.mem.Allocator) !void {
    std.debug.print("Installing 7-Zip...\n", .{});
     
    // Get executable directory path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Create the destination path in the lib directory
    const lib_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "portman", "lib", "7zr" });
    defer allocator.free(lib_path);

    // Create the lib directory if it doesn't exist
    try std.fs.cwd().makePath(lib_path);

    // Set up the destination file path
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ lib_path, "7zr.exe" });
    defer allocator.free(dest_path);

    // Prepare curl command
    const args = [_][]const u8{
        "curl",
        "-L", // Follow redirects
        "-o",
        dest_path,
        "https://www.7-zip.org/a/7zr.exe",
    };

    // Execute curl
    var child = std.process.Child.init(&args, allocator);
    const term = try child.spawnAndWait();
    
    if (term != .Exited or term.Exited != 0) {
        std.debug.print("Failed to download 7-Zip\n", .{});
        return error.DownloadFailed;
    }

    std.debug.print("7-Zip downloaded successfully to {s}\n", .{dest_path});

    // Create and save package metadata
    const new_package = Package{
        .name = "7zr",
        .path = "7zr.exe",
        .keyword = "7zr",
        .description = "7-Zip is a file archiver with a high compression ratio.",
        .global = false,
    };
    try add_package_info(allocator, new_package);
}

fn add_package_info(allocator: std.mem.Allocator, package: Package) !void {
    // Get executable directory path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Construct path to packages.json
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "portman", "lib", "packages.json"});
    defer allocator.free(packages_path);
    
    // Read existing file
    const file = try std.fs.cwd().openFile(packages_path, .{ .mode = .read_write });
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Parse existing JSON
    const parsed = try std.json.parseFromSlice(
        PackageFile,
        allocator,
        content,
        .{},
    );
    defer parsed.deinit();

    // Create new packages array with one more slot
    var new_packages = try allocator.alloc(Package, parsed.value.package.len + 1);
    defer allocator.free(new_packages);

    // Copy existing packages
    @memcpy(new_packages[0..parsed.value.package.len], parsed.value.package);

    // Add new package
    new_packages[new_packages.len - 1] = package;

    // Create new PackageFile with updated packages
    const new_package_file = PackageFile{ .package = new_packages };

    // Convert to JSON string
    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(new_package_file, .{}, string.writer());

    // Write back to file
    try file.seekTo(0);
    try file.writeAll(string.items);
    try file.setEndPos(string.items.len);
}