//this is the file that will run the portman executable
// it should check args and run the appropriate command

const std = @import("std");

// Define the root structure
const PackageFile = struct {
    package: []Package,
};

// Update Package struct to match your JSON structure
const Package = struct {
    name: []const u8,
    path: []const u8,
    keyword: []const u8,
    description: []const u8,
    global: bool,
};

fn readLineFixed() ![]const u8 {
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
    for (parsed.value.package) |package| {
        if (std.mem.eql(u8, package.keyword, keyword)) {
            // Create a new Package with duplicated strings
            return Package{
                .name = try allocator.dupe(u8, package.name),
                .path = try allocator.dupe(u8, package.path),
                .keyword = try allocator.dupe(u8, package.keyword),
                .description = try allocator.dupe(u8, package.description),
                .global = package.global,  // Add this field
            };
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

fn remove_package_info(allocator: std.mem.Allocator, package: Package) !void {
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

    // Create new packages array with one less slot
    var new_packages = try allocator.alloc(Package, parsed.value.package.len - 1);
    defer allocator.free(new_packages);

    // Copy packages except the one to remove
    var new_index: usize = 0;
    for (parsed.value.package) |existing_package| {
        if (!std.mem.eql(u8, existing_package.keyword, package.keyword)) {
            new_packages[new_index] = existing_package;
            new_index += 1;
        }
    }

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

    // If package is global, remove the batch file
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
    
    // Get keywords from Package objects using parse_package_info
    for (packages, 0..) |package, i| {
        if (try parse_package_info(allocator, package.keyword)) |pkg| {
            keywords[i] = pkg.keyword;
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
        const input = readLineFixed() catch {
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
    // On Windows, we create a .cmd file instead of a .sh file
    const script_path = try std.fs.path.join(allocator, &[_][]const u8{
        exe_dir, "..", "bin", 
        try std.fmt.allocPrint(allocator, "{s}.cmd", .{keyword})
    });
    defer allocator.free(script_path);

    // Windows batch script format
    const script_content = try std.fmt.allocPrint(allocator,
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

fn install_package(allocator: std.mem.Allocator, package_path: []const u8, is_global: bool) !void {
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

    const package_name = std.fs.path.basename(package_path);
    std.debug.print("Package name: {s}\n", .{package_name});

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
    std.debug.print("Enter the keyword for the package: ", .{});
    const keyword = try readLineFixed();
    const keyword_copy = try allocator.dupe(u8, keyword);
    defer allocator.free(keyword_copy);

    std.debug.print("Enter the description for the package: ", .{});
    const description = try readLineFixed();
    const desc_copy = try allocator.dupe(u8, description);
    defer allocator.free(desc_copy);
    
    if (is_global) {
        var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
        
        // Create the destination path in the lib directory
        const lib_path = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "..", "lib", package_name });
        defer allocator.free(lib_path);

        // Copy all package files to the lib directory
        std.debug.print("Copying package files to {s}...\n", .{lib_path});
        try copyPackageFiles(allocator, package_path, lib_path);
        
        // Create the command script
        try createGlobalScript(allocator, exe_dir, keyword_copy, package_name, selected_exe);
    }

    // Create and save package metadata
    const new_package = Package{
        .name = try allocator.dupe(u8, package_name),
        .path = try allocator.dupe(u8, selected_exe),
        .keyword = keyword_copy,
        .description = desc_copy,
        .global = is_global,  // Add this field
    };
    try add_package_info(allocator, new_package);
}

fn globalize_package(allocator: std.mem.Allocator, package: []const u8, is_add: bool) !void {
    _ = allocator;
    if (is_add) {
        std.debug.print("Adding package to global list: {s}\n", .{package});
    } else {
        std.debug.print("Removing package from global list: {s}\n", .{package});
    }
}

fn remove_package(allocator: std.mem.Allocator, keyword: []const u8) !void {
    // Get the package info first
    if (try parse_package_info(allocator, keyword)) |package| {
        try remove_package_info(allocator, package);
        std.debug.print("Successfully removed package: {s}\n", .{keyword});
    } else {
        std.debug.print("Package not found: {s}\n", .{keyword});
        return error.PackageNotFound;
    }
}

pub fn run_portman() !void {
    std.debug.print("Running Portman...\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get command line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    
    // Skip the executable name
    _ = args.skip();

    // Check if there are any arguments
    if (args.next()) |command| {
        if (std.mem.eql(u8, command, "install")) {
            if (args.next()) |package| {
                var is_global = false;
                // Check for -g flag
                if (args.next()) |flag| {
                    if (std.mem.eql(u8, flag, "-g")) {
                        is_global = true;
                    }
                }
                try install_package(allocator, package, is_global);
            } else {
                std.debug.print("Error: Package path is required\n", .{});
                std.debug.print("Usage: portman install <package path> [-g]\n", .{});
                return;
            }
        } else if (std.mem.eql(u8, command, "global")) {
            if (args.next()) |package| {
                if (args.next()) |flag| {
                    if (std.mem.eql(u8, flag, "-a")) {
                        try globalize_package(allocator, package, true);
                    }
                    else if (std.mem.eql(u8, flag, "-r")) {
                        try globalize_package(allocator, package, false);
                    }
                    else {
                        std.debug.print("Use -a or -r to add or remove\n", .{});
                        std.debug.print("portman global <package> -a\n", .{});
                        std.debug.print("portman global <package> -r\n", .{});
                        return;
                    }
                }
            }
        } else if (std.mem.eql(u8, command, "remove")) {
            if (args.next()) |package| {
                try remove_package(allocator, package);
            } else {
                std.debug.print("Error: Package name is required\n", .{});
                std.debug.print("Usage: portman remove <package-name>\n", .{});
            }
        } else if (std.mem.eql(u8, command, "list")) {
            const keywords = try get_packages(allocator);
            for (keywords) |keyword| {
                std.debug.print("Available package: {s}\n", .{keyword});
            }
        } else if (try parse_package_info(allocator, command)) |package| {
            // Found the package, now execute it
            var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
            const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
            
            // Construct the full path to the executable
            const exe_path = try std.fs.path.join(allocator, &[_][]const u8{
                exe_dir, "..", "lib", package.name, package.path
            });
            defer allocator.free(exe_path);

            // Collect remaining arguments
            var child_args = std.ArrayList([]const u8).init(allocator);
            defer child_args.deinit();
            
            // Add the executable path as the first argument
            try child_args.append(exe_path);
            
            // Add any remaining arguments
            while (args.next()) |arg| {
                try child_args.append(arg);
            }

            // Create child process
            var child = std.process.Child.init(child_args.items, allocator);
            _ = try child.spawnAndWait();
        } else {
            // No arguments provided, show help
            std.debug.print("Usage: portman <command> [options]\n", .{});
            std.debug.print("Commands:\n", .{});
            std.debug.print("  install <package>     Install a package\n", .{});
            std.debug.print("  install <package> -g  Install a package globally\n", .{});
            std.debug.print("  global <package> -a   Add package to global list\n", .{});
            std.debug.print("  global <package> -r   Remove package from global list\n", .{});
            std.debug.print("  remove <package>      Remove a package\n", .{});
            std.debug.print("  link <path>           Link a package from elsewhere\n", .{});
            std.debug.print("  list                  List all available packages\n", .{});
        }
    }
}