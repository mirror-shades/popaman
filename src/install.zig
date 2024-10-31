const std = @import("std");
const windows = std.os.windows;

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
        root_dir 
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
}

pub fn createInstallBat(output_path: []const u8) !void {
    const batch_contents =
        \\@echo off
        \\setlocal enabledelayedexpansion
        \\
        \\REM Get the directory of the batch file
        \\set "portman=%~dp0"
        \\if "%portman:~-1%"=="\" set "portman=%portman:~0,-1%"
        \\
        \\REM Set PORTMAN_HOME environment variable
        \\setx PORTMAN_HOME "%portman%"
        \\
        \\REM Set the paths
        \\set "bin_path=%portman%\bin"
        \\
        \\REM Add PORTMAN_HOME\bin to PATH if not already present
        \\echo %PATH% | findstr /I /C:"%bin_path%" >nul
        \\if errorlevel 1 (
        \\    setx PATH "%PATH%;%bin_path%"
        \\    echo Added %bin_path% to PATH.
        \\) else (
        \\    echo %bin_path% is already in PATH.
        \\)
        \\endlocal
        \\
    ;

    const file = try std.fs.createFileAbsolute(output_path, .{});
    defer file.close();
    try file.writeAll(batch_contents);
}
