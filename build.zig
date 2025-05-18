const std = @import("std");
const process = std.process;

pub fn build(b: *std.Build) void {
    // Standard target options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "install-popaman",
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = "src/main.zig",
        } },
        .target = target,
        .optimize = optimize,
    });

    // Windows-specific resource file
    if (target.result.os.tag == .windows) {
        exe.addWin32ResourceFile(.{
            .file = .{ .src_path = .{
                .owner = b,
                .sub_path = "assets/app.rc",
            } },
        });
    }

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // Create test step
    const test_step = b.step("test", "Run tests");
    const tests = b.addTest(.{
        .root_source_file = .{ .src_path = .{
            .owner = b,
            .sub_path = "src/main.zig",
        } },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);

    // Create release step
    const release_step = b.step("release", "Create release packages");
    const create_release = CreateRelease.create(b, exe, target);
    release_step.dependOn(&create_release.step);
}

const CreateRelease = struct {
    step: std.Build.Step,
    builder: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,

    pub fn create(b: *std.Build, exe: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) *CreateRelease {
        const self = b.allocator.create(CreateRelease) catch unreachable;
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "create-release",
                .owner = b,
                .makeFn = make,
            }),
            .builder = b,
            .exe = exe,
            .target = target,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const self = @as(*CreateRelease, @ptrCast(@alignCast(step)));
        const b = self.builder;

        // Create release directory
        const cwd = std.fs.cwd();
        try cwd.makePath("release");

        // Copy executable to release directory
        const exe_path = self.exe.getEmittedBin().getPath(b);
        const release_exe = try std.fs.path.join(b.allocator, &[_][]const u8{ "release", std.fs.path.basename(exe_path) });
        try std.fs.copyFileAbsolute(exe_path, release_exe, .{});

        // Create archives if popaman directory exists
        if (cwd.access("popaman", .{})) |_| {
            // Create zip archive
            const zip_cmd = if (self.target.result.os.tag == .windows)
                &[_][]const u8{ "powershell", "Compress-Archive", "-Path", "popaman", "-DestinationPath", "release/popaman.zip", "-Force" }
            else
                &[_][]const u8{ "zip", "-r", "release/popaman.zip", "popaman" };

            const zip_result = try process.Child.run(.{
                .allocator = b.allocator,
                .argv = zip_cmd,
            });
            if (zip_result.stderr.len > 0) {
                std.debug.print("Warning creating zip: {s}\n", .{zip_result.stderr});
            }

            // Create tar.gz archive
            const tar_cmd = &[_][]const u8{ "tar", "-czf", "release/popaman.tar.gz", "popaman" };
            const tar_result = try process.Child.run(.{
                .allocator = b.allocator,
                .argv = tar_cmd,
            });
            if (tar_result.stderr.len > 0) {
                std.debug.print("Warning creating tar.gz: {s}\n", .{tar_result.stderr});
            }

            // Create 7z archive if 7zr exists
            const seven_zip_path = try std.fs.path.join(b.allocator, &[_][]const u8{ "popaman", "lib", "7zr", "7zr" });
            if (cwd.access(seven_zip_path, .{})) |_| {
                const seven_z_cmd = &[_][]const u8{ seven_zip_path, "a", "release/popaman.7z", "./popaman/*" };
                const seven_z_result = try process.Child.run(.{
                    .allocator = b.allocator,
                    .argv = seven_z_cmd,
                });
                if (seven_z_result.stderr.len > 0) {
                    std.debug.print("Warning creating 7z: {s}\n", .{seven_z_result.stderr});
                }
            } else |_| {
                std.debug.print("Warning: 7zr not found, skipping 7z archive\n", .{});
            }
        } else |_| {
            std.debug.print("Warning: popaman directory not found, skipping archives\n", .{});
        }
    }
};
