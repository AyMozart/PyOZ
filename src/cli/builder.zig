const std = @import("std");
const builtin = @import("builtin");
const project = @import("project.zig");

/// Python configuration detected from the system
pub const PythonConfig = struct {
    version_major: u8,
    version_minor: u8,
    version_str: []const u8,
    include_dir: []const u8,
    lib_dir: ?[]const u8,
    lib_name: []const u8,

    pub fn deinit(self: *PythonConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.version_str);
        allocator.free(self.include_dir);
        if (self.lib_dir) |ld| allocator.free(ld);
        allocator.free(self.lib_name);
    }

    /// Get Python tag for wheel (e.g., "cp310")
    pub fn pythonTag(self: PythonConfig) [8]u8 {
        var buf: [8]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "cp{d}{d}", .{ self.version_major, self.version_minor }) catch unreachable;
        return buf;
    }
};

/// Detect Python configuration using python3-config
pub fn detectPython(allocator: std.mem.Allocator) !PythonConfig {
    // Get Python version
    const version_result = try runCommand(allocator, &.{
        "python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')",
    });
    defer allocator.free(version_result);
    const version_trimmed = std.mem.trim(u8, version_result, &std.ascii.whitespace);

    // Parse version
    var version_major: u8 = 3;
    var version_minor: u8 = 0;
    if (std.mem.indexOf(u8, version_trimmed, ".")) |dot| {
        version_major = std.fmt.parseInt(u8, version_trimmed[0..dot], 10) catch 3;
        version_minor = std.fmt.parseInt(u8, version_trimmed[dot + 1 ..], 10) catch 0;
    }

    const version_str = try allocator.dupe(u8, version_trimmed);
    errdefer allocator.free(version_str);

    // Get include directory
    const includes_result = try runCommand(allocator, &.{ "python3-config", "--includes" });
    defer allocator.free(includes_result);

    var include_dir: []const u8 = "";
    var it = std.mem.tokenizeAny(u8, includes_result, " \t\n");
    while (it.next()) |token| {
        if (std.mem.startsWith(u8, token, "-I")) {
            include_dir = try allocator.dupe(u8, token[2..]);
            break;
        }
    }

    if (include_dir.len == 0) {
        allocator.free(version_str);
        return error.PythonNotFound;
    }
    errdefer allocator.free(include_dir);

    // Get library directory (optional)
    var lib_dir: ?[]const u8 = null;
    if (runCommand(allocator, &.{ "python3-config", "--ldflags" })) |ldflags_result| {
        defer allocator.free(ldflags_result);
        var ld_it = std.mem.tokenizeAny(u8, ldflags_result, " \t\n");
        while (ld_it.next()) |token| {
            if (std.mem.startsWith(u8, token, "-L")) {
                lib_dir = try allocator.dupe(u8, token[2..]);
                break;
            }
        }
    } else |_| {}

    // Construct library name
    const lib_name = try std.fmt.allocPrint(allocator, "python{s}", .{version_str});

    return PythonConfig{
        .version_major = version_major,
        .version_minor = version_minor,
        .version_str = version_str,
        .include_dir = include_dir,
        .lib_dir = lib_dir,
        .lib_name = lib_name,
    };
}

/// Build result with path to the compiled module
pub const BuildResult = struct {
    module_path: []const u8,
    module_name: []const u8,

    pub fn deinit(self: *BuildResult, allocator: std.mem.Allocator) void {
        allocator.free(self.module_path);
        allocator.free(self.module_name);
    }
};

/// Build the extension module (shared library)
/// Returns the path to the built .so/.pyd file
pub fn buildModule(allocator: std.mem.Allocator, release: bool) !BuildResult {
    // Load project configuration
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
            return err;
        }
        std.debug.print("Error: Failed to parse pyproject.toml\n", .{});
        return err;
    };
    defer config.deinit(allocator);

    // Determine build type display string
    const optimize_setting = config.getOptimize();
    const build_type = if (release) "Release" else if (optimize_setting.len > 0) optimize_setting else "Debug";
    std.debug.print("Building {s} v{s} ({s})...\n", .{ config.name, config.getVersion(), build_type });

    // Detect Python configuration
    var python = detectPython(allocator) catch |err| {
        std.debug.print("Error: Could not detect Python. Make sure python3 and python3-config are in PATH.\n", .{});
        return err;
    };
    defer python.deinit(allocator);

    std.debug.print("  Python {s} detected\n", .{python.version_str});
    std.debug.print("  Module: {s}\n", .{config.getModulePath()});

    // Determine output filename based on platform
    const ext = switch (builtin.os.tag) {
        .windows => ".pyd",
        else => ".so",
    };

    // Check if build.zig exists
    const cwd = std.fs.cwd();
    const has_build_zig = blk: {
        cwd.access("build.zig", .{}) catch break :blk false;
        break :blk true;
    };

    if (has_build_zig) {
        std.debug.print("  Using build.zig\n", .{});

        // Determine optimization level:
        // - If --release flag is passed, always use ReleaseFast
        // - Otherwise, use the optimize setting from pyproject.toml (empty = debug)
        var argv_buf: [3][]const u8 = undefined;
        var argv_len: usize = 2;
        argv_buf[0] = "zig";
        argv_buf[1] = "build";

        var optimize_arg_buf: [64]u8 = undefined;
        const optimize_value = if (release) "ReleaseFast" else config.getOptimize();
        if (optimize_value.len > 0) {
            const optimize_arg = std.fmt.bufPrint(&optimize_arg_buf, "-Doptimize={s}", .{optimize_value}) catch "-Doptimize=ReleaseFast";
            argv_buf[2] = optimize_arg;
            argv_len = 3;
        }

        const argv: []const []const u8 = argv_buf[0..argv_len];

        var child = std.process.Child.init(argv, allocator);
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        const term = try child.spawnAndWait();
        if (term.Exited != 0) {
            std.debug.print("\nBuild failed!\n", .{});
            return error.BuildFailed;
        }

        const module_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ config.name, ext });
        const module_path = try std.fmt.allocPrint(allocator, "zig-out/lib/{s}", .{module_name});

        return BuildResult{
            .module_path = module_path,
            .module_name = module_name,
        };
    } else {
        std.debug.print("Error: build.zig not found. Please create a build.zig file.\n", .{});
        std.debug.print("Run 'pyoz init --path' to generate one in the current directory.\n", .{});
        return error.NoBuildZig;
    }
}

/// Build and install in development mode (symlink to site-packages or local)
pub fn developMode(allocator: std.mem.Allocator) !void {
    // Load project configuration for display
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
            return err;
        }
        return err;
    };
    defer config.deinit(allocator);

    std.debug.print("Installing {s} in development mode...\n", .{config.name});

    // Build the module (debug mode for develop)
    var result = try buildModule(allocator, false);
    defer result.deinit(allocator);

    // Get absolute path for the built module
    var abs_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_built_path = std.fs.cwd().realpath(result.module_path, &abs_path_buf) catch |err| {
        std.debug.print("Error: Built module not found at {s}\n", .{result.module_path});
        return err;
    };

    // Try to get Python site-packages directory
    const site_result = runCommand(allocator, &.{
        "python3", "-c", "import site; print(site.getsitepackages()[0])",
    }) catch {
        // Fall back to local symlink
        try createLocalSymlink(allocator, abs_built_path, result.module_name, config.name);
        return;
    };
    defer allocator.free(site_result);
    const site_dir = std.mem.trim(u8, site_result, &std.ascii.whitespace);

    const target_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ site_dir, result.module_name });
    defer allocator.free(target_path);

    // Try to create symlink in site-packages
    if (builtin.os.tag == .windows) {
        std.fs.copyFileAbsolute(abs_built_path, target_path, .{}) catch |err| {
            std.debug.print("Warning: Could not copy to site-packages ({s})\n", .{@errorName(err)});
            try createLocalSymlink(allocator, abs_built_path, result.module_name, config.name);
            return;
        };
        std.debug.print("\nCopied to: {s}\n", .{target_path});
    } else {
        std.fs.deleteFileAbsolute(target_path) catch {};
        std.posix.symlink(abs_built_path, target_path) catch |err| {
            if (err == error.AccessDenied) {
                std.debug.print("Warning: Permission denied for site-packages. Creating local symlink.\n", .{});
            }
            try createLocalSymlink(allocator, abs_built_path, result.module_name, config.name);
            return;
        };
        std.debug.print("\nSymlinked to: {s}\n", .{target_path});
    }

    std.debug.print("\nDevelopment install complete!\n", .{});
    std.debug.print("Test with: python3 -c \"import {s}; print({s}.add(2, 3))\"\n", .{ config.name, config.name });
}

fn createLocalSymlink(allocator: std.mem.Allocator, abs_built_path: []const u8, module_name: []const u8, project_name: []const u8) !void {
    const cwd = std.fs.cwd();
    cwd.deleteFile(module_name) catch {};
    cwd.symLink(abs_built_path, module_name, .{}) catch |err| {
        std.debug.print("Error: Could not create symlink: {s}\n", .{@errorName(err)});
        std.debug.print("\nManual installation:\n", .{});
        std.debug.print("  ln -sf {s} ./{s}\n", .{ abs_built_path, module_name });
        return err;
    };

    _ = allocator;
    std.debug.print("\nCreated local symlink: ./{s}\n", .{module_name});
    std.debug.print("You can import the module from this directory.\n", .{});
    std.debug.print("Test with: python3 -c \"import {s}; print({s}.add(2, 3))\"\n", .{ project_name, project_name });
}

pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    }) catch return error.CommandFailed;

    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        return error.CommandFailed;
    }

    return result.stdout;
}
