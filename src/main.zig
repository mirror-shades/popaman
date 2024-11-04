const std = @import("std");
const install = @import("install.zig");
const run = @import("run.zig");

pub fn main() !void {
    const installed = try install.verify_install();
    
    if (installed) {
        try run.run_popaman();
    } else {
        try install.install_popaman();
    }
}