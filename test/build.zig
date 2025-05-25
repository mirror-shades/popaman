// build file for the test package to be used by test.py
// this is a simple executable that will be used to test the installation of popaman
const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "test-package",
        .root_source_file = b.path("test_package.zig"),
        .target = b.graph.host,
        .optimize = b.standardOptimizeOption(.{}),
    });

    const target_output = b.addInstallArtifact(exe, .{
        .dest_dir = .{
            .override = .{
                .custom = "test-package",
            },
        },
    });

    b.getInstallStep().dependOn(&target_output.step);
}