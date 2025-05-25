const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "test-package",
        .root_source_file = b.path("test/test_package.zig"),
        .target = b.graph.host,
        .optimize = b.standardOptimizeOption(.{}),
    });

    // Direct installation to prefix root
    const install_step = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .prefix },
        .dest_filename = "test-package", // Optional filename control
    });

    b.getInstallStep().dependOn(&install_step.step);
}