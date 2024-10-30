// # verify that the directory is set up right
// # /
// # /lib
// # /lib/packages.toml
// # /bin
// # /bin/main.exe <- this is the main executable the code will be compiled to
// # if the directory is not set up right, make a new directory in the same place as the main.exe file called portman and set everything up

const std = @import("std");

fn install_portman() !void {
    // Use an arena allocator for all our temporary allocations
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get current executable path
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buffer);
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

    // Determine root directory
    const root_dir = if (std.mem.eql(u8, std.fs.path.basename(exe_dir), "bin")) 
        std.fs.path.dirname(exe_dir) orelse "."
    else
        try std.fs.path.join(allocator, &[_][]const u8{exe_dir, "portman"});

    // Create root dir if needed (no-op if it exists)
    try std.fs.makeDirAbsolute(root_dir);

    // Create lib and bin directories
    const lib_path = try std.fs.path.join(allocator, &[_][]const u8{root_dir, "lib"});
    const bin_path = try std.fs.path.join(allocator, &[_][]const u8{root_dir, "bin"});
    
    try std.fs.makeDirAbsolute(lib_path);
    try std.fs.makeDirAbsolute(bin_path);

    // Create packages.toml
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{lib_path, "packages.toml"});
    const file = try std.fs.createFileAbsolute(packages_path, .{ .exclusive = true });
    file.close();

    // Copy executable if needed
    if (!std.mem.eql(u8, std.fs.path.basename(exe_dir), "bin")) {
        const new_exe_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{bin_path, "portman.exe"}
        );
        try std.fs.copyFileAbsolute(exe_path, new_exe_path, .{});
    }

    std.debug.print("Directory structure verified/created at: {s}\n", .{root_dir});
}

fn verify_install() !bool {
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
        &[_][]const u8{parent_dir, "lib", "packages.toml"}
    );
    
    // Check if both the file exists and is accessible
    const file = std.fs.cwd().openFile(packages_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return false,
            error.AccessDenied => {
                std.debug.print("Warning: Found packages.toml but cannot access it\n", .{});
                return false;
            },
            else => return err,
        }
    };
    defer file.close();
    
    return true;
}

pub fn main() !void {
    // check if portman is installed
    if(try verify_install()) {
        //if installed, skip install proces and run program
        std.debug.print("Portman is already installed.\n", .{});
        // run portman
    } else {
        std.debug.print("Installing Portman...\n", .{});
        try install_portman();
    }
}