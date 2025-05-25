const std = @import("std");
const cmd_helper = @import("cmd_helper.zig");
const Reporting = @import("../utils/reporting.zig");
const Err = @import("../utils/error.zig").ErrorType;

// Define the root structure
const PackageFile = struct {
    package: []Package,
};

const PackageSource = enum {
    Exe,
    Dir,
    Compressed,
    URL,
    Unknown,
};

// the package struct has functions to handle memory allocation and deallocation
const Package = struct {
    name: []const u8,
    path: []const u8,
    keyword: []const u8,
    description: []const u8,
    global: bool,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8, keyword: []const u8, description: []const u8, global: bool) !Package {
        return Package{
            .name = try allocator.dupe(u8, name),
            .path = try allocator.dupe(u8, path),
            .keyword = try allocator.dupe(u8, keyword),
            .description = try allocator.dupe(u8, description),
            .global = global,
        };
    }

    pub fn deinit(self: *const Package, allocator: std.mem.Allocator) void {  
        allocator.free(self.name);
        allocator.free(self.path);
        allocator.free(self.keyword);
        allocator.free(self.description);
    }
};

fn getline() ![]const u8 {
    var buffer: [240]u8 = undefined;
    const stdin = std.io.getStdIn();
    var buffered = std.io.bufferedReader(stdin.reader());
    var reader = buffered.reader();
    
    if (try reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        // Make a copy of the trimmed input
        const trimmed = std.mem.trim(u8, line, &[_]u8{ '\r', '\n', ' ', '\t' });
        // Return just the valid part of the input
        return trimmed[0..trimmed.len];
    }
    
    return error.EndOfStream;
}

fn parse_package_info(allocator: std.mem.Allocator, keyword: []const u8) !?Package {
    // Create buffer for executable path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "..", "lib", "packages.json"});
    defer allocator.free(packages_path);
    
    const file = try std.fs.cwd().openFile(packages_path, .{});
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Parse the JSON content
    const parsed = try std.json.parseFromSlice(
        PackageFile,
        allocator,
        content,
        .{},
    );
    defer parsed.deinit();

    // Search through packages for matching keyword
    for (parsed.value.package) |pkg| {
        if (std.mem.eql(u8, pkg.keyword, keyword)) {
            const new_package = try Package.init(
                allocator,
                pkg.name,
                pkg.path, 
                pkg.keyword,
                pkg.description,
                pkg.global
            );
            return new_package;
        }
    }

    
    return null;
}

fn add_package_info(allocator: std.mem.Allocator, package: Package) !void {
    // Get executable directory path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Construct path to packages.json
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "..", "lib", "packages.json"});
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
    defer {
        // Deinitialize and free new_packages
        for (new_packages) |*pkg| {
            pkg.deinit(allocator);
        }
        allocator.free(new_packages);
    }

    // Copy existing packages using deep copy
    for (parsed.value.package, 0..) |existing_pkg, i| {
        new_packages[i] = try Package.init(
            allocator,
            existing_pkg.name,
            existing_pkg.path,
            existing_pkg.keyword,
            existing_pkg.description,
            existing_pkg.global
        );
    }

    // Add new package (assuming package is already properly allocated)
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

fn remove_package_info(allocator: std.mem.Allocator, package: Package) !void {
    // Get executable directory path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Update packages.json
    try removeFromPackagesJson(allocator, exe_dir, package);
    
    // Remove associated files
    try removePackageFiles(allocator, exe_dir, package);
}

fn removeFromPackagesJson(allocator: std.mem.Allocator, exe_dir: []const u8, package: Package) !void {
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "..", "lib", "packages.json"});
    defer allocator.free(packages_path);
    
    // Read and parse existing file
    const file = try std.fs.cwd().openFile(packages_path, .{ .mode = .read_write });
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(PackageFile, allocator, content, .{});
    defer parsed.deinit();

    // Create filtered package list
    var new_packages = try allocator.alloc(Package, parsed.value.package.len - 1);
    defer {
        for (new_packages) |*pkg| pkg.deinit(allocator);
        allocator.free(new_packages);
    }

    // Copy all packages except the one being removed
    var new_index: usize = 0;
    for (parsed.value.package) |existing_package| {
        if (!std.mem.eql(u8, existing_package.keyword, package.keyword)) {
            new_packages[new_index] = try Package.init(
                allocator,
                existing_package.name,
                existing_package.path,
                existing_package.keyword,
                existing_package.description,
                existing_package.global
            );
            new_index += 1;
        }
    }

    // Write updated package list back to file
    const new_package_file = PackageFile{ .package = new_packages };
    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    
    try std.json.stringify(new_package_file, .{}, string.writer());
    try file.seekTo(0);
    try file.writeAll(string.items);
    try file.setEndPos(string.items.len);
}

fn removePackageFiles(allocator: std.mem.Allocator, exe_dir: []const u8, package: Package) !void {
    // Remove global batch file if needed
    if (package.global) {
        const batch_path = try std.fs.path.join(allocator, &[_][]const u8{
            exe_dir, 
            "..", 
            "bin", 
            try std.fmt.allocPrint(allocator, "{s}.cmd", .{package.keyword})
        });
        defer allocator.free(batch_path);
        
        std.fs.deleteFileAbsolute(batch_path) catch |err| {
            std.debug.print("Warning: Could not delete batch file: {any}\n", .{err});
        };
    }

    // Remove package directory from lib
    const lib_path = try std.fs.path.join(allocator, &[_][]const u8{
        exe_dir,
        "..",
        "lib",
        package.name,
    });
    defer allocator.free(lib_path);

    std.fs.deleteTreeAbsolute(lib_path) catch |err| {
        std.debug.print("Warning: Could not delete package directory: {any}\n", .{err});
    };
}

fn get_packages(allocator: std.mem.Allocator) ![][]const u8 {
    std.debug.print("Getting packages...\n", .{});
    
    // Create buffer for executable path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "..", "lib", "packages.json"});
    defer allocator.free(packages_path);
    
    const file = try std.fs.cwd().openFile(packages_path, .{});
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Parse the JSON content
    const parsed = try std.json.parseFromSlice(
        PackageFile,
        allocator,
        content,
        .{},
    );
    defer parsed.deinit();
    
    // Access the parsed data through the package field
    const packages = parsed.value.package;
    var keywords = try allocator.alloc([]const u8, packages.len);
    errdefer {
        for (keywords) |keyword| {
            allocator.free(keyword);
        }
        allocator.free(keywords);
    }

    // Get keywords from Package objects using parse_package_info
    for (packages, 0..) |package, i| {
        if (try parse_package_info(allocator, package.keyword)) |pkg| {
            defer pkg.deinit(allocator);
            keywords[i] = try allocator.dupe(u8, pkg.keyword);
        }
    }
    
    return keywords;
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
                if (std.fs.path.dirname(dest_file_path)) |parent| {
                    std.fs.cwd().makePath(parent) catch |err| {
                        std.debug.print("Warning: Could not create parent directory {s}: {any}\n", .{ parent, err });
                        continue;
                    };
                }

                // Copy the file
                std.fs.copyFileAbsolute(source_file_path, dest_file_path, .{}) catch |err| {
                    std.debug.print("Warning: Could not copy file {s}: {any}\n", .{ entry.path, err });
                    continue;
                };
            },
            .directory => {
                std.fs.cwd().makePath(dest_file_path) catch |err| {
                    std.debug.print("Warning: Could not create directory {s}: {any}\n", .{ dest_file_path, err });
                    continue;
                };
            },
            else => {
                std.debug.print("Warning: Skipping unsupported file type for {s}\n", .{entry.path});
                continue;
            },
        }
    }
}

fn findExecutables(allocator: std.mem.Allocator, dir: std.fs.Dir, package_path: []const u8) !std.ArrayList([]const u8) {
    var exe_paths = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (exe_paths.items) |path| {
            allocator.free(path);
        }
        exe_paths.deinit();
    }

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ package_path, entry.path });
            defer allocator.free(full_path);
            
            if (std.mem.endsWith(u8, entry.path, ".exe") or 
                std.mem.endsWith(u8, entry.path, ".sh") or 
                !std.mem.containsAtLeast(u8, entry.path, 1, ".")) {
                try exe_paths.append(try allocator.dupe(u8, entry.path));
            }
        }
    }

    return exe_paths;
}

fn selectExecutable(exe_paths: std.ArrayList([]const u8)) ![]const u8 {
    if (exe_paths.items.len == 0) {
        return error.NoExecutablesFound;
    }

    while (true) {
        std.debug.print("Available executables\n", .{});
        std.debug.print("if you are unsure refer to the tools documentation\n", .{});
        for (exe_paths.items, 0..) |exe, i| {
            std.debug.print("{d}: {s}\n", .{ i + 1, exe });
        }

        std.debug.print("Enter the number of the executable to use (1-{d}): ", .{exe_paths.items.len});
        const input = getline() catch {
            std.debug.print("Error reading input. Please try again.\n", .{});
            continue;
        };
        
        const selection = std.fmt.parseInt(usize, input, 10) catch {
            std.debug.print("Please enter a number between 1 and {d}\n", .{exe_paths.items.len});
            continue;
        };
        
        if (selection < 1 or selection > exe_paths.items.len) {
            std.debug.print("Please enter a number between 1 and {d}\n", .{exe_paths.items.len});
            continue;
        }

        return exe_paths.items[selection - 1];
    }
}

fn createGlobalScript(allocator: std.mem.Allocator, exe_dir: []const u8, keyword: []const u8, package_name: []const u8, exe_path: []const u8) !void {
    const script_path = try std.fs.path.join(allocator, &[_][]const u8{
        exe_dir, "..", "bin", 
        try std.fmt.allocPrint(allocator, "{s}.cmd", .{keyword})
    });
    defer allocator.free(script_path);

    // For linked packages, use the path directly from package.json
    const script_content = if (std.mem.startsWith(u8, package_name, "link@")) 
        try std.fmt.allocPrint(allocator,
            \\@echo off
            \\set "EXE_PATH={s}"
            \\"%EXE_PATH%" %*
            \\
        , .{exe_path})  // Use the full path from package.json
        else try std.fmt.allocPrint(allocator,
            \\@echo off
            \\set "EXE_PATH=%~dp0..\lib\{s}\{s}"
            \\"%EXE_PATH%" %*
            \\
        , .{ package_name, exe_path });
    defer allocator.free(script_content);

    const script_file = try std.fs.cwd().createFile(script_path, .{});
    defer script_file.close();
    try script_file.writeAll(script_content);
}

fn determine_if_local_dir(package_path: []const u8) !PackageSource {
    // Check if it's a local directory
    var dir = std.fs.cwd().openDir(package_path, .{ .iterate = true }) catch {
        Reporting.throwError("Package directory does not exist: {s}\n", .{package_path}, Err.FileNotFound);
        return Err.FileNotFound;
    };
    dir.close();
    return PackageSource.Dir;

}

fn determine_source_type(package_path: []const u8) !PackageSource {
    if (std.mem.startsWith(u8, package_path, "http://") or 
        std.mem.startsWith(u8, package_path, "https://")) {
        std.debug.print("Package is a url\n", .{});
        return PackageSource.URL;
    }
    else if (std.mem.endsWith(u8, package_path, ".7z")) {
        return PackageSource.Compressed;
    }
    //to be added later
    else if (std.mem.endsWith(u8, package_path, ".tar") or 
             std.mem.endsWith(u8, package_path, ".gz") or 
             std.mem.endsWith(u8, package_path, ".zip") or 
             std.mem.endsWith(u8, package_path, ".rar")) {
        return PackageSource.Unknown;
    }
    else if (std.mem.endsWith(u8, package_path, ".exe") or
             std.mem.endsWith(u8, package_path, ".sh") or
             std.mem.endsWith(u8, package_path, ".cmd") or
             std.mem.endsWith(u8, package_path, ".bat")) {
        return PackageSource.Exe;
    }
    else {
        return PackageSource.Unknown;
    }
}

fn install_local_dir(allocator: std.mem.Allocator, package_path: []const u8, is_global: bool) !void {
    // Open and verify package directory
    var dir = std.fs.cwd().openDir(package_path, .{ .iterate = true }) catch |err| {
        if (err == error.NotDir or err == error.FileNotFound) {
            std.debug.print("Package directory does not exist: {s}\n", .{package_path});
            return;
        }
        std.debug.print("Error opening directory: {any}\n", .{err});
        return err;
    };
    defer dir.close();

    // Find executables
    var exe_paths = try findExecutables(allocator, dir, package_path);
    defer {
        for (exe_paths.items) |path| {
            allocator.free(path);
        }
        exe_paths.deinit();
    }

    // Select executable
    const selected_exe = selectExecutable(exe_paths) catch |err| {
        switch (err) {
            error.NoExecutablesFound => {
                std.debug.print("No executable files found in the package\n", .{});
                return;
            },
            else => return err,
        }
    };

    // Get package metadata
    var keyword_copy: []u8 = undefined;
    while (true) {
        std.debug.print("Enter the keyword for the package: ", .{});
        const keyword = try getline();
        if (keyword.len == 0) {
            std.debug.print("Keyword cannot be empty. Please try again.\n", .{});
            continue;
        }
        keyword_copy = try allocator.dupe(u8, keyword);
        break;
    }
    defer allocator.free(keyword_copy);

    std.debug.print("Enter the description for the package: ", .{});
    const description = try getline();
    const desc_copy = try allocator.dupe(u8, description);
    defer allocator.free(desc_copy);

    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Create the destination path in the lib directory using the keyword
    const lib_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "..", "lib", keyword_copy });
    defer allocator.free(lib_path);

    // Copy all package files to the lib directory
    std.debug.print("Copying package files to {s}...\n", .{lib_path});
    try copyPackageFiles(allocator, package_path, lib_path);
    
    if (is_global) {
        // Create the command script only if global
        try createGlobalScript(allocator, exe_dir, keyword_copy, keyword_copy, selected_exe);
    }

    // Create and save package metadata
    const new_package = Package{
        .name = try allocator.dupe(u8, keyword_copy),
        .path = try allocator.dupe(u8, selected_exe),
        .keyword = keyword_copy,
        .description = desc_copy,
        .global = is_global,
    };
    try add_package_info(allocator, new_package);
}

fn download_package(allocator: std.mem.Allocator, package_path: []const u8) !void {
    // Create a temporary directory for downloads if it doesn't exist
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    const temp_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "..", "temp" });
    defer allocator.free(temp_dir);
    
    try std.fs.cwd().makePath(temp_dir);

    // Extract filename from URL
    const url_basename = std.fs.path.basename(package_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir, url_basename });
    defer allocator.free(output_path);

    // Prepare curl command
    const args = [_][]const u8{
        "curl",
        "-L", // Follow redirects
        "-o",
        output_path,
        package_path,
    };

    // Execute curl
    var child = std.process.Child.init(&args, allocator);
    const term = try child.spawnAndWait();
    
    if (term != .Exited or term.Exited != 0) {
        std.debug.print("Failed to download package: {s}\n", .{package_path});
        return error.DownloadFailed;
    }

    // Now that we have the file, determine its type and install it
    const source_type = try determine_source_type(output_path);
    switch (source_type) {
        .Exe => try install_exe(allocator, output_path, false),
        .Compressed => try install_compressed(allocator, output_path, false),
        else => {
            std.debug.print("Package is not a supported format\n", .{});
            return error.Unknown;
        },
    }

    // Clean up the temporary file
    std.fs.deleteFileAbsolute(output_path) catch |err| {
        std.debug.print("Warning: Could not delete temporary file: {any}\n", .{err});
    };
}

fn install_exe(allocator: std.mem.Allocator, package_path: []const u8, is_global: bool) !void {
    // Get executable directory path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);

    // Create a temporary directory for the exe
    const temp_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "..", "temp", "exe_install" });
    defer allocator.free(temp_dir);

    // Create the temp directory if it doesn't exist
    try std.fs.cwd().makePath(temp_dir);
    defer std.fs.deleteTreeAbsolute(temp_dir) catch |err| {
        std.debug.print("Warning: Could not delete temporary directory: {any}\n", .{err});
    };

    // Copy the exe to the temp directory
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_dir, std.fs.path.basename(package_path) });
    defer allocator.free(dest_path);

    try std.fs.copyFileAbsolute(package_path, dest_path, .{});

    // Now install from the temp directory, which will handle getting the keyword and setting up the package
    try install_local_dir(allocator, temp_dir, is_global);
}

fn install_compressed(allocator: std.mem.Allocator, package_path: []const u8, is_global: bool) !void {
    // Get executable directory path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Create a temporary extraction directory
    const temp_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "..", "temp", "extract" });
    defer allocator.free(temp_dir);
    
    try std.fs.cwd().makePath(temp_dir);
    defer std.fs.deleteTreeAbsolute(temp_dir) catch |err| {
        std.debug.print("Warning: Could not delete temporary directory: {any}\n", .{err});
    };

    // Get absolute paths
    const abs_package_path = try std.fs.path.resolve(allocator, &[_][]const u8{package_path});
    defer allocator.free(abs_package_path);
    
    const abs_temp_dir = try std.fs.path.resolve(allocator, &[_][]const u8{temp_dir});
    defer allocator.free(abs_temp_dir);

    // Debug prints
    std.debug.print("Extracting from: {s}\n", .{abs_package_path});
    std.debug.print("Extracting to: {s}\n", .{abs_temp_dir});

    const args = [_][]const u8{
        "x",
        abs_package_path,  // Remove quotes, pass path directly
        try std.fmt.allocPrint(allocator, "-o{s}", .{abs_temp_dir}),  // Remove quotes, just concatenate
        "-y"
    };
    defer allocator.free(args[2]);

    // Debug print the command
    std.debug.print("Running 7zr with args:", .{});
    for (args) |arg| {
        std.debug.print(" {s}", .{arg});
    }
    std.debug.print("\n", .{});

    // Run 7zr through the package manager
    try run_package(allocator, "7zr", &args);

    // Now that we've extracted the files, install from the temp directory
    try install_local_dir(allocator, abs_temp_dir, is_global);
}

fn install_package(allocator: std.mem.Allocator, package_path: []const u8, is_global: bool) !void {
    //make an enum for exe, dir, and compressed
    var package_source: PackageSource = try determine_if_local_dir(package_path); // Added try
    std.debug.print("Package source: {}\n", .{package_source});
    if(package_source == PackageSource.Unknown) {
        package_source = try determine_source_type(package_path);
        std.debug.print("Package source: {}\n", .{package_source});
        if (package_source == PackageSource.URL ) {
            try download_package(allocator, package_path);
        }
        else if (package_source == PackageSource.Exe) {
            try install_exe(allocator, package_path, is_global);
        }
        else if (package_source == PackageSource.Compressed) {
            try install_compressed(allocator, package_path, is_global);
        }
        return;
    }
    try install_local_dir(allocator, package_path, is_global);
}

fn globalize_package(allocator: std.mem.Allocator, keyword: []const u8, is_add: bool) !void {
    // Get package info
    if (try parse_package_info(allocator, keyword)) |pkg| {
        defer pkg.deinit(allocator);
        // Get executable directory path
        var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);

        if (is_add) {
            // Create the batch file using the full path from package info
            try createGlobalScript(allocator, exe_dir, pkg.keyword, pkg.name, pkg.path);
            std.debug.print("Added global script for: {s}\n", .{pkg.keyword});
        } else {
            // Remove the batch file
            const batch_path = try std.fs.path.join(allocator, &[_][]const u8{
                exe_dir,
                "..",
                "bin",
                try std.fmt.allocPrint(allocator, "{s}.cmd", .{pkg.keyword})
            });
            defer allocator.free(batch_path);

            std.fs.deleteFileAbsolute(batch_path) catch |err| {
                std.debug.print("Warning: Could not delete batch file: {any}\n", .{err});
                return err;
            };
            std.debug.print("Removed global script for: {s}\n", .{pkg.keyword});
        }
    } else {
        std.debug.print("Package not found: {s}\n", .{keyword});
        return error.PackageNotFound;
    }
}

fn remove_package(allocator: std.mem.Allocator, keyword: []const u8) !void {
    // Get the package info first
    if (try parse_package_info(allocator, keyword)) |pkg| {
        defer pkg.deinit(allocator);
        try remove_package_info(allocator, pkg);
        std.debug.print("Successfully removed package: {s}\n", .{keyword});
    } else {
        std.debug.print("Package not found: {s}\n", .{keyword});
        return error.PackageNotFound;
    }
}

fn link_package(allocator: std.mem.Allocator, path: []const u8, is_global: bool) !void {
    std.debug.print("Linking package from: {s}\n", .{path});
    
    // Open and verify package directory
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
        if (err == error.NotDir or err == error.FileNotFound) {
            std.debug.print("Package directory does not exist: {s}\n", .{path});
            return;
        }
        std.debug.print("Error opening directory: {any}\n", .{err});
        return err;
    };
    defer dir.close();

    // Get the base directory name and create the linked name
    const base_name = std.fs.path.basename(path);
    const linked_name = try std.fmt.allocPrint(allocator, "link@{s}", .{base_name});
    defer allocator.free(linked_name);

    // Find executables
    var exe_paths = try findExecutables(allocator, dir, path);
    defer {
        for (exe_paths.items) |exe_path| {
            allocator.free(exe_path);
        }
        exe_paths.deinit();
    }

    // Select executable
    const selected_exe = selectExecutable(exe_paths) catch |err| {
        switch (err) {
            error.NoExecutablesFound => {
                std.debug.print("No executable files found in the package\n", .{});
                return;
            },
            else => return err,
        }
    };

    // Get package metadata
    var keyword_copy: []u8 = undefined;
    while (true) {
        std.debug.print("Enter the keyword for the package: ", .{});
        const keyword = try getline();
        if (keyword.len == 0) {
            std.debug.print("Keyword cannot be empty. Please try again.\n", .{});
            continue;
        }
        keyword_copy = try allocator.dupe(u8, keyword);
        break;
    }
    defer allocator.free(keyword_copy);

    std.debug.print("Enter the description for the package: ", .{});
    const description = try getline();
    const desc_copy = try allocator.dupe(u8, description);
    defer allocator.free(desc_copy);

    // Get absolute path for the linked package
    const abs_path = try std.fs.realpathAlloc(allocator, path);
    defer allocator.free(abs_path);

    if (is_global) {
        var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
        
        // Create the global script with the full absolute path
        const full_exe_path = try std.fs.path.join(allocator, &[_][]const u8{ abs_path, selected_exe });
        try createGlobalScript(allocator, exe_dir, keyword_copy, linked_name, full_exe_path);
    }

    // Create and save package metadata
    const new_package = Package{
        .name = try allocator.dupe(u8, linked_name),
        .path = try std.fs.path.join(allocator, &[_][]const u8{ abs_path, selected_exe }),
        .keyword = keyword_copy,
        .description = desc_copy,
        .global = is_global,
    };
    try add_package_info(allocator, new_package);

    std.debug.print("Successfully linked package: {s}\n", .{linked_name});
}

fn run_package(allocator: std.mem.Allocator, keyword: []const u8, extra_args: []const []const u8) !void {
    if (try parse_package_info(allocator, keyword)) |pkg| {
        defer pkg.deinit(allocator);
        var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
        
        // Construct the full path to the executable
        const exe_path = if (std.mem.startsWith(u8, pkg.name, "link@"))
            try allocator.dupe(u8, pkg.path)  // Use the absolute path directly
        else try std.fs.path.join(allocator, &[_][]const u8{
            exe_dir, "..", "lib", pkg.name, pkg.path
        });
        defer allocator.free(exe_path);

        // Collect all arguments
        var child_args = std.ArrayList([]const u8).init(allocator);
        defer child_args.deinit();
        
        // Add the executable path as the first argument
        try child_args.append(exe_path);
        
        // Add any extra arguments
        for (extra_args) |arg| {
            try child_args.append(arg);
        }

        // Create child process
        var child = std.process.Child.init(child_args.items, allocator);
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;
        
        const term = try child.spawnAndWait();
        if (term != .Exited or term.Exited != 0) {
            return error.CommandFailed;
        }
    } else {
        std.debug.print("Package not found: {s}\n", .{keyword});
        return error.PackageNotFound;
    }
}

fn help_menu() !void {
    std.debug.print("Usage: popaman <command> [options]\n", .{});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  install <package>         Install a package\n", .{});
    std.debug.print("  install <package> -g      Install a package globally\n", .{});
    std.debug.print("  globalize <package> -a    Add package to global list\n", .{});
    std.debug.print("  globalize <package> -r    Remove package from global list\n", .{});
    std.debug.print("  remove <package>          Remove a package\n", .{});
    std.debug.print("  link <path>               Link a package from elsewhere\n", .{});
    std.debug.print("  list                      List all available packages\n", .{});
    std.debug.print("  list -v                   List all available packages with descriptions\n", .{});
}

pub fn run_popaman() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get command line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    // Skip the executable name
    _ = args.skip();

    // Show help if no arguments
    const command = args.next() orelse {
        try help_menu();
        return;
    };

    // Handle install command
    if (cmd_helper.isInstallCommand(command)) {
        const package = args.next() orelse {
            std.debug.print("Error: Package path is required\n", .{});
            std.debug.print("Usage: popaman install <package path> [-g]\n", .{});
            return;
        };
        const is_global = if (args.next()) |flag| cmd_helper.isGlobalFlag(flag) else false;
        try install_package(allocator, package, is_global);
        return;
    }

    // Handle globalize command
    if (cmd_helper.isGlobalizeCommand(command)) {
        const package = args.next() orelse {
            std.debug.print("Error: Package name is required\n", .{});
            return;
        };
        const flag = args.next() orelse {
            std.debug.print("Error: Flag (-a or -r) is required\n", .{});
            return;
        };
        
        if (cmd_helper.isAddFlag(flag)) {
            try globalize_package(allocator, package, true);
            return;
        }
        if (cmd_helper.isRemoveFlag(flag)) {
            try globalize_package(allocator, package, false);
            return;
        }
        
        std.debug.print("Use -a or -r to add or remove\n", .{});
        std.debug.print("popaman global <package> -a\n", .{});
        std.debug.print("popaman global <package> -r\n", .{});
        return;
    }

    // Handle remove command
    if (cmd_helper.isRemoveCommand(command)) {
        const package = args.next() orelse {
            std.debug.print("Error: Package name is required\n", .{});
            std.debug.print("Usage: popaman remove <package-name>\n", .{});
            return;
        };
        try remove_package(allocator, package);
        return;
    }

    // Handle link command
    if (cmd_helper.isLinkCommand(command)) {
        const path = args.next() orelse {
            std.debug.print("Error: Path is required\n", .{});
            std.debug.print("Usage: popaman link <path>\n", .{});
            return;
        };
        const is_global = if (args.next()) |flag| cmd_helper.isGlobalFlag(flag) else false;
        try link_package(allocator, path, is_global);
        return;
    }

    // Handle list command
    if (cmd_helper.isListCommand(command)) {
        const packages = try get_packages(allocator);
        const verbose = if (args.next()) |flag| cmd_helper.isVerboseFlag(flag) else false;
        
        if (verbose) {
            std.debug.print("Available packages with descriptions:\n", .{});
            for (packages) |keyword| {
                if (try parse_package_info(allocator, keyword)) |pkg| {
                    defer pkg.deinit(allocator);
                    std.debug.print("\n({s}\\{s}) {s} \nGlobal: {}\nDescription: {s}\n", .{
                        pkg.name, 
                        pkg.path,
                        pkg.keyword, 
                        pkg.global,
                        pkg.description
                    });
                }   
            }
            return;
        }

        for (packages) |keyword| {
            std.debug.print("Available package: {s}\n", .{keyword});
        }
        return;
    }

    // Try to run as package command
    if (try parse_package_info(allocator, command)) |pkg| {
        defer pkg.deinit(allocator);
        var remaining_args = std.ArrayList([]const u8).init(allocator);
        defer remaining_args.deinit();
        
        while (args.next()) |arg| {
            try remaining_args.append(arg);
        }

        try run_package(allocator, command, remaining_args.items);
        return;
    }

    // If no other command matched, show help
    std.debug.print("Invalid command: {s}\n", .{command});
    try help_menu();
}


