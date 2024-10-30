const std = @import("std");
const install = @import("install.zig");
const run = @import("run.zig");

pub fn main() !void {
    const installed = try install.verify_install();
    
    if (installed) {
        std.debug.print("Portman is already installed.\n", .{});
        try run.run_portman();
    } else {
        try install.install_portman();
    }
}