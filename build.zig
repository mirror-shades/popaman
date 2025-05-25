const std = @import("std");

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "test-package",  // This controls the output filename
        .root_source_file = b.path("test_package.zig"),
        .target = b.graph.host,
        .optimize = b.standardOptimizeOption(.{}),
    });

    // Get the executable's output path
    const exe_output = exe.getEmittedBin();

    // Install directly to prefix root
    const install_step = b.addInstallFile(
        exe_output,
        b.pathJoin(&.{ "", "test-package" }), // Empty string forces root dir
    );

    b.getInstallStep().dependOn(&install_step.step);
}