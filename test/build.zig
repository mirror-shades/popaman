pub fn build(b: *std.Build) void {
    // Standard target options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "hello",
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = "test_package.zig",
        } },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);
}