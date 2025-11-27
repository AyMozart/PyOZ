const std = @import("std");
const version = @import("version");

const project = @import("project.zig");
const builder = @import("builder.zig");
const wheel = @import("wheel.zig");

/// Initialize a new PyOZ project
pub fn init(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var project_name: ?[]const u8 = null;
    var show_help = false;
    var in_current_dir = false;
    var local_pyoz_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--path") or std.mem.eql(u8, arg, "-p")) {
            in_current_dir = true;
        } else if (std.mem.eql(u8, arg, "--local") or std.mem.eql(u8, arg, "-l")) {
            // Next arg must be the path
            if (i + 1 < args.len and !std.mem.startsWith(u8, args[i + 1], "-")) {
                i += 1;
                local_pyoz_path = args[i];
            } else {
                std.debug.print("Error: --local requires a path argument\n", .{});
                std.debug.print("  pyoz init --local /path/to/PyOZ myproject\n", .{});
                return error.MissingLocalPath;
            }
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            project_name = arg;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz init [options] [name]
            \\
            \\Create a new PyOZ project.
            \\
            \\Arguments:
            \\  name                Project name (required unless using --path)
            \\
            \\Options:
            \\  -p, --path          Initialize in current directory instead of creating new one
            \\  -l, --local <path>  Use local PyOZ path instead of fetching from URL
            \\  -h, --help          Show this help message
            \\
            \\Examples:
            \\  pyoz init myproject                        # Create with URL dependency
            \\  pyoz init --local /path/to/PyOZ myproject  # Use local PyOZ path
            \\  pyoz init --path                           # Initialize in current directory
            \\  pyoz init --path mymod                     # Initialize in current dir with name 'mymod'
            \\
        , .{});
        return;
    }

    try project.create(allocator, project_name, in_current_dir, local_pyoz_path);
}

/// Build the extension module and create a wheel
pub fn build(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var release = false;
    var show_help = false;
    var generate_stubs = true;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--release") or std.mem.eql(u8, arg, "-r")) {
            release = true;
        } else if (std.mem.eql(u8, arg, "--debug") or std.mem.eql(u8, arg, "-d")) {
            release = false;
        } else if (std.mem.eql(u8, arg, "--no-stubs")) {
            generate_stubs = false;
        } else if (std.mem.eql(u8, arg, "--stubs")) {
            generate_stubs = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz build [options]
            \\
            \\Build the extension module and create a wheel package.
            \\
            \\Options:
            \\  -d, --debug    Build in debug mode (default)
            \\  -r, --release  Build in release mode (optimized)
            \\  --stubs        Generate .pyi type stub file (default)
            \\  --no-stubs     Do not generate .pyi type stub file
            \\  -h, --help     Show this help message
            \\
            \\The wheel will be placed in the dist/ directory.
            \\
        , .{});
        return;
    }

    const wheel_path = try wheel.buildWheel(allocator, release, generate_stubs);
    defer allocator.free(wheel_path);
}

/// Build and install in development mode
pub fn develop(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var show_help = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz develop
            \\
            \\Build the module and install it in development mode.
            \\Creates a symlink so changes are reflected after rebuilding.
            \\
            \\Options:
            \\  -h, --help  Show this help message
            \\
        , .{});
        return;
    }

    try builder.developMode(allocator);
}

/// Publish wheel(s) to PyPI
pub fn publish(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var show_help = false;
    var test_pypi = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--test") or std.mem.eql(u8, arg, "-t")) {
            test_pypi = true;
        }
    }

    if (show_help) {
        std.debug.print(
            \\Usage: pyoz publish [options]
            \\
            \\Publish wheel(s) from dist/ to PyPI.
            \\
            \\Options:
            \\  -t, --test  Upload to TestPyPI instead of PyPI
            \\  -h, --help  Show this help message
            \\
            \\Authentication:
            \\  Set PYPI_TOKEN environment variable with your API token.
            \\  For TestPyPI, use TEST_PYPI_TOKEN instead.
            \\
            \\  Generate tokens at:
            \\    PyPI:     https://pypi.org/manage/account/token/
            \\    TestPyPI: https://test.pypi.org/manage/account/token/
            \\
        , .{});
        return;
    }

    try wheel.publish(allocator, test_pypi);
}
