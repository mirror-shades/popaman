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
            };
        }
    }
    
    return null;
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

fn install_package(allocator: std.mem.Allocator, package: []const u8, is_global: bool) !void {
    

    std.debug.print("Enter the keyword for the package: ", .{});
    const keyword = try readLineFixed();
    const keyword_copy = try allocator.dupe(u8, keyword);
    defer allocator.free(keyword_copy);

    std.debug.print("Enter the description for the package: ", .{});
    const description = try readLineFixed();
    const desc_copy = try allocator.dupe(u8, description);
    defer allocator.free(desc_copy);
    
    if (is_global) {
        std.debug.print("Installing package and adding to global list: {s}\n", .{package});
    } else {
        std.debug.print("Installing package: {s}\n", .{package});
    }

    //name: package
    //keyword: keyword_copy
    //description: desc_copy
    //global: is_global
}

fn globalize_package(allocator: std.mem.Allocator, package: []const u8, is_add: bool) !void {
    _ = allocator;
    if (is_add) {
        std.debug.print("Adding package to global list: {s}\n", .{package});
    } else {
        std.debug.print("Removing package from global list: {s}\n", .{package});
    }
}

fn remove_package(allocator: std.mem.Allocator, package: []const u8) !void {
    _ = allocator;
    std.debug.print("Removing package: {s}\n", .{package});
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
            }
        } else if (std.mem.eql(u8, command, "list")) {
            const keywords = try get_packages(allocator);
            for (keywords) |keyword| {
                std.debug.print("Available package: {s}\n", .{keyword});
            }
        }
    } else {
        // No arguments provided, show help
        std.debug.print("Usage: portman <command> [options]\n", .{});
        std.debug.print("Commands:\n", .{});
        std.debug.print("  install <package>     Install a package\n", .{});
        std.debug.print("  install <package> -g  Install a package globally\n", .{});
        std.debug.print("  global <package> -a   Add package to global list\n", .{});
        std.debug.print("  global <package> -r   Remove package from global list\n", .{});
        std.debug.print("  remove <package>      Remove a package\n", .{});
        std.debug.print("  list                  List all available packages\n", .{});
    }
}