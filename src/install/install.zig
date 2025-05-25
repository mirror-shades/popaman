const std = @import("std");
const windows = std.os.windows;
const builtin = @import("builtin");

// Update Package struct to match your JSON structure
const Package = struct {
    name: []const u8,
    path: []const u8,
    keyword: []const u8,
    description: []const u8,
    global: bool,
};

const PackageFile = struct {
    package: []Package,
};

const SupportedPlatform = struct {
    os: std.Target.Os.Tag,
    arch: std.Target.Cpu.Arch,
};

const supported_platforms = [_]SupportedPlatform{
    .{ .os = .windows, .arch = .x86_64 },
    .{ .os = .windows, .arch = .aarch64 },
    .{ .os = .linux, .arch = .x86_64 },
    .{ .os = .linux, .arch = .aarch64 },
    .{ .os = .macos, .arch = .x86_64 },
    .{ .os = .macos, .arch = .aarch64 },
};

fn isPlatformSupported() bool {
    for (supported_platforms) |platform| {
        if (platform.os == builtin.os.tag and platform.arch == builtin.cpu.arch) {
            return true;
        }
    }
    return false;
}

fn expandHomeDir(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (path.len == 0 or path[0] != '~') return allocator.dupe(u8, path);

    // Get home directory based on platform
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => std.process.getEnvVarOwned(allocator, "USERPROFILE") catch {
            return error.HomeNotFound;
        },
        else => |e| return e,
    };
    defer allocator.free(home);

    if (path.len == 1) return allocator.dupe(u8, home);

    // Handle both Unix-style and Windows-style paths
    const path_separator = if (std.fs.path.sep == '\\') '\\' else '/';
    if (path[1] == path_separator) {
        return std.fs.path.join(allocator, &[_][]const u8{
            home,
            path[2..],
        });
    }

    return allocator.dupe(u8, path);
}

fn create_popaman_directory(arg_root_dir: []const u8) !void {
    // Add null check for empty string case
    if (arg_root_dir.len > 0) {
        std.debug.print("Installing popaman to {s}\n", .{arg_root_dir});
    } else {
        std.debug.print("Installing popaman to current directory\n", .{});
    }
    // Use an arena allocator for all our temporary allocations
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get current executable path
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buffer);
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

    // Expand home directory if path starts with ~
    const expanded_root_dir = try expandHomeDir(allocator, arg_root_dir);
    defer allocator.free(expanded_root_dir);

    // Create the directory first if it doesn't exist
    if (expanded_root_dir.len > 0) {
        try std.fs.cwd().makePath(expanded_root_dir);
    }

    // Convert arg_root_dir to absolute path if provided
    const base_dir = if (expanded_root_dir.len > 0)
        try std.fs.cwd().realpathAlloc(allocator, expanded_root_dir) // This is freed by arena
    else
        exe_dir;

    // This join result isn't explicitly freed, but it's handled by the arena
    const root_dir = if (std.mem.eql(u8, std.fs.path.basename(base_dir), "bin"))
        std.fs.path.dirname(base_dir) orelse "."
    else
        try std.fs.path.join(allocator, &[_][]const u8{ base_dir, "popaman" });

    // These joins aren't explicitly freed, but they're handled by the arena
    const lib_path = try std.fs.path.join(allocator, &[_][]const u8{ root_dir, "lib" });
    const bin_path = try std.fs.path.join(allocator, &[_][]const u8{ root_dir, "bin" });

    std.debug.print("Creating lib directory: {s}\n", .{lib_path});
    // Use makePath instead of makeDirAbsolute to create parent directories
    std.fs.cwd().makePath(lib_path) catch |err| {
        std.debug.print("Error creating lib dir: {any}\n", .{err});
        return err;
    };

    std.debug.print("Creating bin directory: {s}\n", .{bin_path});
    // Use makePath for bin directory as well
    std.fs.cwd().makePath(bin_path) catch |err| {
        std.debug.print("Error creating bin dir: {any}\n", .{err});
        return err;
    };

    // Create packages.json
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{ lib_path, "packages.json" });
    std.debug.print("Creating packages.json: {s}\n", .{packages_path});

    // Create or truncate the file and write initial JSON structure
    const file = try std.fs.cwd().createFile(packages_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(
        \\{
        \\  "package": []
        \\}
    );

    // Copy executable if needed
    const exe_name = if (builtin.os.tag == .windows) "popaman.exe" else "popaman";
    const new_exe_path = try std.fs.path.join(allocator, &[_][]const u8{ bin_path, exe_name });
    std.debug.print("Copying installer to: {s}\n", .{new_exe_path});
    try std.fs.copyFileAbsolute(exe_path, new_exe_path, .{});

    // Make the file executable on Unix-like systems
    if (builtin.os.tag != .windows) {
        const exe_file = try std.fs.openFileAbsolute(new_exe_path, .{ .mode = .read_write });
        defer exe_file.close();
        try exe_file.chmod(0o755);
    }

    std.debug.print("Directory structure verified/created at: {s}\n", .{root_dir});
}

// checks to see if popaman is alreadyinstalled
pub fn verify_install() !bool {
    // Use arena allocator instead of page_allocator directly
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buffer);
    const exe_dir = std.fs.path.dirname(exe_path) orelse return error.InvalidPath;
    const parent_dir = std.fs.path.dirname(exe_dir) orelse return error.InvalidPath;

    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{ parent_dir, "lib", "packages.json" });

    // Check if both the file exists and is accessible
    const file = std.fs.cwd().openFile(packages_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => return false,
            error.AccessDenied => {
                std.debug.print("Warning: Found packages.json but cannot access it\n", .{});
                return false;
            },
            else => return err,
        }
    };
    defer file.close();

    return true;
}

pub fn createInstallBat(install_bat_path: []const u8, uninstall_bat_path: []const u8) !void {
    const batch_contents =
        \\@echo off
        \\setlocal enabledelayedexpansion
        \\
        \\REM Get the directory of the batch file
        \\set "popaman_path=%~dp0"
        \\if "%popaman_path:~-1%"=="\" set "popaman_path=%popaman_path:~0,-1%"
        \\cd "%popaman_path%"
        \\cd ..
        \\set "popaman_path=%cd%"
        \\
        \\REM Set popaman_HOME environment variable
        \\setx popaman_HOME "%popaman_path%"
        \\
        \\REM Set the paths
        \\set "bin_path=%popaman_path%\bin"
        \\
        \\REM Get current PATH from registry
        \\for /f "tokens=2*" %%a in ('reg query "HKEY_CURRENT_USER\Environment" /v PATH') do set "current_path=%%b"
        \\
        \\REM Check if our bin_path is already present
        \\echo !current_path! | findstr /I /C:"%bin_path%" >nul
        \\if errorlevel 1 (
        \\    REM Append to existing PATH (preserving all existing entries)
        \\    setx PATH "!current_path!;%bin_path%"
        \\    echo Added %bin_path% to PATH.
        \\) else (
        \\    echo %bin_path% is already in PATH.
        \\)
        \\
        \\echo.
        \\echo popaman environment setup complete.
        \\echo Please restart your command prompt or terminal for the changes to take effect.
        \\
        \\endlocal
        \\pause
        \\
    ;

    const file = try std.fs.createFileAbsolute(install_bat_path, .{});
    defer file.close();
    try file.writeAll(batch_contents);

    const unpath_contents =
        \\@echo off
        \\setlocal enabledelayedexpansion
        \\
        \\REM Get the directory of the batch file
        \\set "popaman_path=%~dp0"
        \\if "%popaman_path:~-1%"=="\" set "popaman_path=%popaman_path:~0,-1%"
        \\cd "%popaman_path%"
        \\cd ..
        \\set "popaman_path=%cd%"
        \\
        \\REM Set the paths
        \\set "bin_path=%popaman_path%\bin"
        \\
        \\REM Get current PATH from registry
        \\for /f "tokens=2*" %%a in ('reg query "HKEY_CURRENT_USER\Environment" /v PATH') do set "current_path=%%b"
        \\
        \\REM Remove popaman_HOME environment variable
        \\reg delete "HKEY_CURRENT_USER\Environment" /v popaman_HOME /f >nul 2>&1
        \\
        \\REM Remove bin_path from PATH if present
        \\set "new_path=!current_path!"
        \\set "new_path=!new_path:;%bin_path%=!"
        \\set "new_path=!new_path:%bin_path%;=!"
        \\set "new_path=!new_path:%bin_path%=!"
        \\
        \\REM Update PATH only if it was changed
        \\if not "!new_path!"=="!current_path!" (
        \\    setx PATH "!new_path!"
        \\    echo Removed %bin_path% from PATH.
        \\) else (
        \\    echo %bin_path% was not found in PATH.
        \\)
        \\
        \\echo.
        \\echo popaman environment cleanup complete.
        \\echo Please restart your command prompt or terminal for the changes to take effect.
        \\
        \\endlocal
        \\pause
        \\
    ;

    const unpath_file = try std.fs.createFileAbsolute(uninstall_bat_path, .{});
    defer unpath_file.close();
    try unpath_file.writeAll(unpath_contents);
}

fn copyPackageFiles(allocator: std.mem.Allocator, source_path: []const u8, dest_dir: []const u8) !void {
    // Create the destination directory if it doesn't exist
    try std.fs.cwd().makePath(dest_dir);

    var source_dir = try std.fs.cwd().openDir(source_path, .{ .iterate = true });
    defer source_dir.close();

    var walker = try source_dir.walk(allocator);
    errdefer walker.deinit();
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const source_file_path = try std.fs.path.join(allocator, &[_][]const u8{ source_path, entry.path });
        defer allocator.free(source_file_path);

        const dest_file_path = try std.fs.path.join(allocator, &[_][]const u8{ dest_dir, entry.path });
        defer allocator.free(dest_file_path);

        switch (entry.kind) {
            .file => {
                // Create parent directory if needed
                const dest_parent = std.fs.path.dirname(dest_file_path);
                if (dest_parent) |parent| {
                    try std.fs.cwd().makePath(parent);
                }

                // Copy the file
                try std.fs.copyFileAbsolute(source_file_path, dest_file_path, .{});
            },
            .directory => {
                try std.fs.cwd().makePath(dest_file_path);
            },
            else => {},
        }
    }
}

const SevenZipConfig = struct {
    url: ?[]const u8,
    filename: []const u8,
    install_cmd: ?[]const []const u8,
};

fn detectLinuxDistro(allocator: std.mem.Allocator) ![]const u8 {
    // Try to read /etc/os-release
    const os_release = std.fs.openFileAbsolute("/etc/os-release", .{}) catch |err| {
        std.debug.print("Warning: Could not open /etc/os-release: {any}\n", .{err});
        return error.UnknownDistro;
    };
    defer os_release.close();

    const content = try os_release.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(content);

    // Look for ID= line
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "ID=")) {
            const id = line[3..];
            // Remove quotes if present
            if (id.len >= 2 and id[0] == '"' and id[id.len - 1] == '"') {
                return try allocator.dupe(u8, id[1 .. id.len - 1]);
            }
            return try allocator.dupe(u8, id);
        }
    }

    return error.UnknownDistro;
}

fn get7ZipConfig() !SevenZipConfig {
    return switch (builtin.os.tag) {
        .windows => .{
            .url = "https://www.7-zip.org/a/7zr.exe",
            .filename = "7zr.exe",
            .install_cmd = null,
        },
        .linux => {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const allocator = arena.allocator();

            const distro = detectLinuxDistro(allocator) catch |err| {
                std.debug.print("Warning: Could not detect Linux distribution: {any}\n", .{err});
                return .{
                    .url = null,
                    .filename = "7zr",
                    .install_cmd = &[_][]const u8{
                        "which",
                        "7zr",
                    },
                };
            };
            defer allocator.free(distro);

            if (std.mem.eql(u8, distro, "arch")) {
                return .{
                    .url = null,
                    .filename = "7zr",
                    .install_cmd = &[_][]const u8{
                        "pacman",
                        "-S",
                        "--noconfirm",
                        "p7zip",
                    },
                };
            } else if (std.mem.eql(u8, distro, "debian") or std.mem.eql(u8, distro, "ubuntu")) {
                return .{
                    .url = null,
                    .filename = "7zr",
                    .install_cmd = &[_][]const u8{
                        "apt-get",
                        "install",
                        "-y",
                        "p7zip-full",
                    },
                };
            } else if (std.mem.eql(u8, distro, "fedora")) {
                return .{
                    .url = null,
                    .filename = "7zr",
                    .install_cmd = &[_][]const u8{
                        "dnf",
                        "install",
                        "-y",
                        "p7zip",
                    },
                };
            } else {
                // For unknown distributions, just check if 7zr is available
                return .{
                    .url = null,
                    .filename = "7zr",
                    .install_cmd = &[_][]const u8{
                        "which",
                        "7zr",
                    },
                };
            }
        },
        .macos => .{
            .url = null,
            .filename = "7zr",
            .install_cmd = &[_][]const u8{
                "brew",
                "install",
                "p7zip",
            },
        },
        else => unreachable, // We check platform support earlier
    };
}

fn add_package_info(allocator: std.mem.Allocator, package: Package, install_dir: []const u8) !void {
    // Construct path to packages.json
    const packages_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, "lib", "packages.json" });
    defer allocator.free(packages_path);

    std.debug.print("Writing package info to: {s}\n", .{packages_path});

    // Open file in read-write mode
    const file = try std.fs.cwd().openFile(packages_path, .{ .mode = .read_write });
    defer file.close();

    // Read existing content
    var content: []u8 = undefined;
    if (file.readToEndAlloc(allocator, std.math.maxInt(usize))) |data| {
        content = data;
    } else |err| {
        if (err == error.EndOfStream) {
            // If file is empty, write initial JSON structure
            try file.writeAll(
                \\{
                \\  "package": []
                \\}
            );
            try file.seekTo(0);
            content = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        } else {
            return err;
        }
    }
    defer allocator.free(content);

    // Parse existing JSON
    var parsed = try std.json.parseFromSlice(
        PackageFile,
        allocator,
        content,
        .{},
    );
    defer parsed.deinit();

    // Create new array with space for all packages
    var new_packages = try allocator.alloc(Package, parsed.value.package.len + 1);
    defer allocator.free(new_packages);

    // Copy existing packages
    for (parsed.value.package, 0..) |src_package, i| {
        new_packages[i] = Package{
            .name = try allocator.dupe(u8, src_package.name),
            .path = try allocator.dupe(u8, src_package.path),
            .keyword = try allocator.dupe(u8, src_package.keyword),
            .description = try allocator.dupe(u8, src_package.description),
            .global = src_package.global,
        };
    }

    // Add new package
    new_packages[new_packages.len - 1] = Package{
        .name = try allocator.dupe(u8, package.name),
        .path = try allocator.dupe(u8, package.path),
        .keyword = try allocator.dupe(u8, package.keyword),
        .description = try allocator.dupe(u8, package.description),
        .global = package.global,
    };

    // Create new PackageFile with updated packages
    const new_package_file = PackageFile{ .package = new_packages };

    // Convert to JSON string
    var string = std.ArrayList(u8).init(allocator);
    defer string.deinit();
    try std.json.stringify(new_package_file, .{}, string.writer());

    // Write back to file
    try file.seekTo(0);
    try file.writeAll(string.items);
    try file.setEndPos(string.items.len);

    // Clean up allocated package strings
    for (new_packages) |*pkg| {
        allocator.free(pkg.name);
        allocator.free(pkg.path);
        allocator.free(pkg.keyword);
        allocator.free(pkg.description);
    }
}

fn install_7zip(allocator: std.mem.Allocator, install_dir: []const u8) !void {
    std.debug.print("Installing 7-Zip...\n", .{});

    const config = try get7ZipConfig();

    // Create the lib directory if it doesn't exist
    const lib_path = try std.fs.path.join(allocator, &[_][]const u8{ install_dir, "lib", "7zr" });
    try std.fs.cwd().makePath(lib_path);
    defer allocator.free(lib_path);

    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ lib_path, config.filename });
    defer allocator.free(dest_path);

    switch (builtin.os.tag) {
        .windows => {
            // Download 7zr.exe for Windows
            if (config.url) |url| {
                const args = [_][]const u8{
                    "curl",
                    "-L", // Follow redirects
                    "-o",
                    dest_path,
                    url,
                };

                const result = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &args,
                });

                if (result.stderr.len > 0) {
                    std.debug.print("Warning downloading 7-Zip: {s}\n", .{result.stderr});
                }

                std.debug.print("7-Zip downloaded successfully to {s}\n", .{dest_path});
            }
        },
        .linux, .macos => {
            if (config.install_cmd) |cmd| {
                // Try to install using package manager
                const result = std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = cmd,
                }) catch |err| {
                    switch (err) {
                        error.FileNotFound => {
                            if (builtin.os.tag == .linux) {
                                std.debug.print("Error: Package manager command not found. Please install p7zip manually using your distribution's package manager.\n", .{});
                                if (cmd[0][0] != '/') {
                                    std.debug.print("Note: You may need to run the installer with sudo for package manager access.\n", .{});
                                }
                            } else {
                                std.debug.print("Error: Homebrew not found. Please install p7zip manually using homebrew or another package manager.\n", .{});
                            }
                            return err;
                        },
                        error.AccessDenied => {
                            std.debug.print("Error: Access denied. Please run the installer with sudo.\n", .{});
                            return err;
                        },
                        else => {
                            std.debug.print("Error installing 7-Zip: {any}\n", .{err});
                            return err;
                        },
                    }
                };

                if (result.stderr.len > 0) {
                    std.debug.print("Warning installing 7-Zip: {s}\n", .{result.stderr});
                }

                // Create symlink to system-installed 7zr
                const system_7zr = switch (builtin.os.tag) {
                    .linux => "/usr/bin/7zr",
                    .macos => "/usr/local/bin/7zr",
                    else => unreachable,
                };

                // Remove existing symlink if it exists
                std.fs.deleteFileAbsolute(dest_path) catch |err| switch (err) {
                    error.FileNotFound => {}, // File doesn't exist, which is fine
                    else => |e| {
                        std.debug.print("Warning: Could not remove existing symlink: {any}\n", .{e});
                    },
                };

                // Create new symlink
                std.fs.symLinkAbsolute(system_7zr, dest_path, .{}) catch |err| {
                    std.debug.print("Error creating symlink from {s} to {s}: {any}\n", .{ system_7zr, dest_path, err });
                    return err;
                };
            }
        },
        else => unreachable, // We check platform support earlier
    }

    // Create and save package metadata
    const new_package = Package{
        .name = "7zr",
        .path = config.filename,
        .keyword = "7zr",
        .description = "7-Zip is a file archiver with a high compression ratio.",
        .global = false,
    };
    try add_package_info(allocator, new_package, install_dir);
}

pub fn install_popaman() !void {
    var root_dir: []const u8 = ""; // Default install path
    var force_install = false;
    var skip_path = false; // New flag for -no-path

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Get executable path early
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const exe_path = try std.fs.selfExePath(&buffer);
    const exe_dir = std.fs.path.dirname(exe_path) orelse ".";

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip(); // Skip executable name

    // Process arguments
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-f")) {
            force_install = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-no-path")) {
            skip_path = true;
            continue;
        }
        // If we already have a root_dir, this is an unexpected argument
        if (root_dir.len > 0) {
            std.debug.print("Error: Unexpected argument '{s}'\n", .{arg});
            return error.UnexpectedArgument;
        }
        root_dir = arg;
    }

    if (root_dir.len == 0) {
        const installation_dir = try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "popaman" });

        // confirms the user intends to install to
        std.debug.print("No install path included. popaman will be installed to: {s}? (Y/n) ", .{installation_dir});

        const stdin = std.io.getStdIn().reader();
        var buf: [2]u8 = undefined;
        const amt = try stdin.read(&buf);

        if (amt > 0 and (buf[0] == 'n' or buf[0] == 'N')) {
            std.debug.print("Installation cancelled\n", .{});
            return;
        }

        if (std.fs.cwd().access(installation_dir, .{}) catch null != null) {
            if (force_install) {
                std.debug.print("Force removing existing installation at '{s}'\n", .{installation_dir});
                try std.fs.deleteTreeAbsolute(installation_dir);
            } else {
                std.debug.print("Error: Directory already contains a 'popaman' directory\n", .{});
                return error.popamanDirectoryExists;
            }
        }
    }

    // Store the actual installation directory
    const installation_dir = if (root_dir.len > 0)
        try std.fs.path.join(allocator, &[_][]const u8{ root_dir, "popaman" })
    else
        try std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "popaman" });
    defer allocator.free(installation_dir);

    std.debug.print("Installing popaman...\n", .{});
    try create_popaman_directory(root_dir);

    // Platform-specific PATH setup
    if (!skip_path) {
        switch (builtin.os.tag) {
            .windows => {
                const install_bat_path = try std.fs.path.join(allocator, &[_][]const u8{ installation_dir, "lib", "PATH.bat" });
                const uninstall_bat_path = try std.fs.path.join(allocator, &[_][]const u8{ installation_dir, "lib", "UNPATH.bat" });
                try createInstallBat(install_bat_path, uninstall_bat_path);

                _ = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &[_][]const u8{install_bat_path},
                });
            },
            .linux, .macos => {
                // Create shell script for PATH setup
                const shell_rc = try getShellRcPath(allocator);
                defer allocator.free(shell_rc);

                const bin_path = try std.fs.path.join(allocator, &[_][]const u8{ installation_dir, "bin" });
                defer allocator.free(bin_path);

                // Create parent directory for RC file if needed
                const rc_dir = std.fs.path.dirname(shell_rc) orelse return error.InvalidRcPath;
                std.fs.makeDirAbsolute(rc_dir) catch |err| switch (err) {
                    error.PathAlreadyExists => {},
                    else => return err,
                };

                // Try to open or create the RC file
                const rc_file = try std.fs.openFileAbsolute(shell_rc, .{ .mode = .read_write });
                defer rc_file.close();

                // Read existing content or use empty string
                const content = blk: {
                    if (rc_file.readToEndAlloc(allocator, std.math.maxInt(usize))) |data| {
                        break :blk data;
                    } else |err| {
                        if (err == error.EndOfStream) {
                            break :blk try allocator.dupe(u8, "");
                        }
                        return err;
                    }
                };
                defer allocator.free(content);

                // Create the PATH line based on shell type
                const path_line = if (std.mem.endsWith(u8, shell_rc, "config.fish"))
                    try std.fmt.allocPrint(allocator, "\nset -gx PATH \"{s}\" $PATH\n", .{bin_path})
                else
                    try std.fmt.allocPrint(allocator, "\nexport PATH=\"{s}:$PATH\"\n", .{bin_path});
                defer allocator.free(path_line);

                // Only add the PATH if it's not already there
                if (std.mem.indexOf(u8, content, path_line) == null) {
                    try rc_file.seekFromEnd(0);
                    try rc_file.writeAll(path_line);
                    std.debug.print("Added popaman bin directory to PATH in {s}\n", .{shell_rc});
                    std.debug.print("Please restart your shell or run 'source {s}' to update your PATH\n", .{shell_rc});
                } else {
                    std.debug.print("popaman bin directory already in PATH\n", .{});
                }
            },
            else => {},
        }
    }

    try install_7zip(allocator, installation_dir);
    std.debug.print("popaman installed successfully!\n", .{});
}

fn getShellRcPath(allocator: std.mem.Allocator) ![]const u8 {
    // Try to detect the current shell
    const shell = std.process.getEnvVarOwned(allocator, "SHELL") catch |err| {
        if (err == error.EnvironmentVariableNotFound) return error.ShellNotFound;
        return err;
    };
    defer allocator.free(shell);

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);

    return if (std.mem.endsWith(u8, shell, "bash"))
        std.fs.path.join(allocator, &[_][]const u8{ home, ".bashrc" })
    else if (std.mem.endsWith(u8, shell, "zsh"))
        std.fs.path.join(allocator, &[_][]const u8{ home, ".zshrc" })
    else if (std.mem.endsWith(u8, shell, "fish"))
        std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "fish", "config.fish" })
    else
        error.UnsupportedShell;
}
