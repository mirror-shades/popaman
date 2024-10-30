const std = @import("std");
const install = @import("install.zig");

pub fn main() !void {
    const installed = try install.verify_install();
    
    if (installed) {
        std.debug.print("Portman is already installed.\n", .{});
        // run portman
    } else {
        try install.install_portman();
    }
}