//this is the file that will run the portman executable
// it should check args and run the appropriate command

const std = @import("std");

fn get_packages(allocator: std.mem.Allocator) !void {
    std.debug.print("Getting packages...\n", .{});
    
    // Create buffer for executable path
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    
    // Debug: Print executable directory
    std.debug.print("Executable directory: {s}\n", .{exe_dir});
    
    // Go up from bin/ to the project root, then into lib/
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "..", "lib", "packages.toml"});
    defer allocator.free(packages_path);
    
    // Debug: Print the final path
    std.debug.print("Attempting to read from path: {s}\n", .{packages_path});
    
    const file = try std.fs.cwd().openFile(packages_path, .{});
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);
    
    std.debug.print("File contents:\n{s}\n", .{content});
}

pub fn run_portman() !void {
    std.debug.print("Running Portman...\n", .{});
    try get_packages(std.heap.page_allocator);
}