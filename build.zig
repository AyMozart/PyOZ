const std = @import("std");

/// Python configuration detected from the system
const PythonConfig = struct {
    version: []const u8,
    include_dir: []const u8,
    lib_dir: ?[]const u8,
    lib_name: []const u8,
};

/// Detect Python configuration using python3-config
fn detectPython(b: *std.Build) ?PythonConfig {
    var out_code: u8 = 0;

    // Try to get Python version
    const version_result = b.runAllowFail(
        &.{ "python3", "-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" },
        &out_code,
        .Inherit,
    ) catch return null;
    if (out_code != 0) return null;
    const version = std.mem.trim(u8, version_result, &std.ascii.whitespace);

    // Get include directory
    const include_result = b.runAllowFail(
        &.{ "python3-config", "--includes" },
        &out_code,
        .Inherit,
    ) catch return null;
    if (out_code != 0) return null;

    var include_dir: []const u8 = "";

    // Parse the includes output to extract the path
    var it = std.mem.tokenizeAny(u8, include_result, " \t\n");
    while (it.next()) |token| {
        if (std.mem.startsWith(u8, token, "-I")) {
            include_dir = token[2..];
            break;
        }
    }

    if (include_dir.len == 0) return null;

    // Get library directory (optional)
    var lib_dir: ?[]const u8 = null;
    if (b.runAllowFail(&.{ "python3-config", "--ldflags" }, &out_code, .Inherit)) |ldflags_result| {
        if (out_code == 0) {
            var ld_it = std.mem.tokenizeAny(u8, ldflags_result, " \t\n");
            while (ld_it.next()) |token| {
                if (std.mem.startsWith(u8, token, "-L")) {
                    lib_dir = token[2..];
                    break;
                }
            }
        }
    } else |_| {}

    // Construct library name
    const lib_name = std.fmt.allocPrint(b.allocator, "python{s}", .{version}) catch return null;

    return PythonConfig{
        .version = version,
        .include_dir = include_dir,
        .lib_dir = lib_dir,
        .lib_name = lib_name,
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Sanitizer option
    const sanitize = b.option(bool, "sanitize", "Enable address sanitizer") orelse false;

    // Detect Python on the system
    const python_config = detectPython(b);

    if (python_config == null) {
        std.log.warn("Python not detected! Make sure python3 and python3-config are in PATH.", .{});
    }

    // Create the version module - single source of truth for lib and CLI
    const version_mod = b.addModule("version", .{
        .root_source_file = b.path("src/version.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create the PyOZ module (library)
    const pyoz_mod = b.addModule("PyOZ", .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "version", .module = version_mod },
        },
    });

    // Add Python include path to the module
    if (python_config) |python| {
        pyoz_mod.addIncludePath(.{ .cwd_relative = python.include_dir });
    }

    // ========================================================================
    // Example Python Extension Module
    // ========================================================================

    const example_lib = b.addLibrary(.{
        .name = "example",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/example_module.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "PyOZ", .module = pyoz_mod },
            },
        }),
    });

    // Enable sanitizers if requested
    if (sanitize) {
        example_lib.root_module.sanitize_c = .full;
    }

    // Link against Python
    if (python_config) |python| {
        example_lib.addIncludePath(.{ .cwd_relative = python.include_dir });
        example_lib.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (python.lib_dir) |lib_dir| {
            example_lib.addLibraryPath(.{ .cwd_relative = lib_dir });
        }
        example_lib.linkSystemLibrary(python.lib_name);
    }
    example_lib.linkLibC();

    // Install as .so file
    const install_example = b.addInstallArtifact(example_lib, .{
        .dest_sub_path = "example.so",
    });

    const example_step = b.step("example", "Build the example Python module");
    example_step.dependOn(&install_example.step);

    // ========================================================================
    // Test Suite
    // ========================================================================

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Enable sanitizers if requested
    if (sanitize) {
        tests.root_module.sanitize_c = .full;
    }

    // Link against Python for embedding
    if (python_config) |python| {
        tests.addIncludePath(.{ .cwd_relative = python.include_dir });
        tests.root_module.addIncludePath(.{ .cwd_relative = python.include_dir });
        if (python.lib_dir) |lib_dir| {
            tests.addLibraryPath(.{ .cwd_relative = lib_dir });
        }
        tests.linkSystemLibrary(python.lib_name);
    }
    tests.linkLibC();

    const run_tests = b.addRunArtifact(tests);
    // Tests depend on the example module being built first
    run_tests.step.dependOn(&install_example.step);

    const test_step = b.step("test", "Run the PyOZ test suite");
    test_step.dependOn(&run_tests.step);

    // ========================================================================
    // CLI Executable (pyoz command)
    // ========================================================================

    const cli_exe = b.addExecutable(.{
        .name = "pyoz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "version", .module = version_mod },
            },
        }),
    });

    const install_cli = b.addInstallArtifact(cli_exe, .{});

    const cli_step = b.step("cli", "Build the PyOZ CLI tool");
    cli_step.dependOn(&install_cli.step);

    // Run CLI step for quick testing
    const run_cli = b.addRunArtifact(cli_exe);
    run_cli.step.dependOn(&install_cli.step);
    if (b.args) |args| {
        run_cli.addArgs(args);
    }

    const run_cli_step = b.step("run", "Run the PyOZ CLI tool");
    run_cli_step.dependOn(&run_cli.step);

    // ========================================================================
    // Cross-compile CLI for all major OS/arch pairs
    // ========================================================================

    const release_targets = [_]std.Target.Query{
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
    };

    const release_step = b.step("release", "Build CLI for all platforms (x86_64/aarch64 for Linux/macOS/Windows)");

    for (release_targets) |t| {
        const release_target = b.resolveTargetQuery(t);

        const release_version_mod = b.addModule(b.fmt("version-{s}-{s}", .{
            @tagName(t.cpu_arch.?),
            @tagName(t.os_tag.?),
        }), .{
            .root_source_file = b.path("src/version.zig"),
            .target = release_target,
            .optimize = .ReleaseSmall,
        });

        const release_exe = b.addExecutable(.{
            .name = "pyoz",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/cli/main.zig"),
                .target = release_target,
                .optimize = .ReleaseSmall,
                .strip = true,
                .imports = &.{
                    .{ .name = "version", .module = release_version_mod },
                },
            }),
        });

        // Statically link libc for fully static binaries
        release_exe.linkLibC();

        const target_name = b.fmt("pyoz-{s}-{s}{s}", .{
            @tagName(t.cpu_arch.?),
            @tagName(t.os_tag.?),
            if (t.os_tag.? == .windows) ".exe" else "",
        });

        const install_release = b.addInstallArtifact(release_exe, .{
            .dest_dir = .{ .override = .{ .custom = "release" } },
            .dest_sub_path = target_name,
        });

        release_step.dependOn(&install_release.step);
    }

    // ========================================================================
    // Default step just shows info
    // ========================================================================

    const default_step = b.step("info", "Show build information");
    if (python_config) |python| {
        const info_cmd = b.addSystemCommand(&.{
            "echo",
            std.fmt.allocPrint(b.allocator,
                \\
                \\PyOZ - Python bindings for Zig
                \\==============================
                \\Python version: {s}
                \\Include dir:   {s}
                \\Library:       {s}
                \\
                \\To build the example module:
                \\  zig build example
                \\
                \\To build the CLI tool:
                \\  zig build cli
                \\
                \\Then test the example:
                \\  cd zig-out/lib
                \\  python3 -c "import example; print(example.add(2, 3))"
                \\
            , .{ python.version, python.include_dir, python.lib_name }) catch "Error",
        });
        default_step.dependOn(&info_cmd.step);
    }
}
