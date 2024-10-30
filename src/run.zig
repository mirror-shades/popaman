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

fn get_packages(allocator: std.mem.Allocator) ![][]const u8 {
    std.debug.print("Getting packages...\n", .{});
    
    // Create buffer for executable path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Debug: Print executable directory
    std.debug.print("Executable directory: {s}\n", .{exe_dir});
    
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
    
    // Create duplicates of the strings to ensure they remain valid
    for (packages, 0..) |package, i| {
        keywords[i] = try allocator.dupe(u8, package.keyword);
    }
    
    return keywords;
}

pub fn run_portman() !void {
    std.debug.print("Running Portman...\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const keywords = try get_packages(allocator);
    // No need to manually free keywords as arena allocator will handle it
    
    for (keywords) |keyword| {
        std.debug.print("Keyword: {s}\n", .{keyword});
    }
}