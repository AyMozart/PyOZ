const std = @import("std");
const builtin = @import("builtin");
const project = @import("project.zig");
const builder = @import("builder.zig");
const pypi = @import("pypi.zig");
const zip = @import("zip.zig");
const symreader = @import("symreader.zig");

/// Build a wheel package (.whl)
/// A wheel is a ZIP file with a specific structure:
///   {module}.{ext}                    - The compiled extension
///   {module}.pyi                      - Type stubs (optional)
///   {distribution}-{version}.dist-info/
///     WHEEL                           - Wheel metadata
///     METADATA                        - Package metadata
///     RECORD                          - File hashes
pub fn buildWheel(allocator: std.mem.Allocator, release: bool, generate_stubs: bool) ![]const u8 {
    // Load project configuration
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found. Run 'pyoz init' first.\n", .{});
            return err;
        }
        return err;
    };
    defer config.deinit(allocator);

    // Detect Python for version tag
    var python = builder.detectPython(allocator) catch |err| {
        std.debug.print("Error: Could not detect Python.\n", .{});
        return err;
    };
    defer python.deinit(allocator);

    // Build the module first
    var build_result = try builder.buildModule(allocator, release);
    defer build_result.deinit(allocator);

    std.debug.print("\nCreating wheel package...\n", .{});

    // Create dist directory
    const cwd = std.fs.cwd();
    cwd.makeDir("dist") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Generate wheel filename
    // Format: {distribution}-{version}-{python}-{abi}-{platform}.whl
    const platform_tag = try getPlatformTag(allocator, config.getLinuxPlatformTag());
    defer if (builtin.os.tag == .macos) allocator.free(platform_tag);

    // For ABI3 wheels, use hardcoded Python 3.8 minimum
    // Format: cp38-abi3-{platform}
    // For non-ABI3, use current Python version: cpXY-cpXY-{platform}
    const python_tag = if (config.getAbi3())
        "cp38" // ABI3 hardcoded to Python 3.8
    else
        try std.fmt.allocPrint(allocator, "cp{d}{d}", .{ python.version_major, python.version_minor });
    defer if (!config.getAbi3()) allocator.free(python_tag);

    // ABI tag: "abi3" for ABI3 mode, same as python_tag for non-ABI3
    const abi_tag: []const u8 = if (config.getAbi3()) "abi3" else python_tag;

    const wheel_filename = try std.fmt.allocPrint(
        allocator,
        "{s}-{s}-{s}-{s}-{s}.whl",
        .{ config.name, config.getVersion(), python_tag, abi_tag, platform_tag },
    );
    defer allocator.free(wheel_filename);

    const wheel_path = try std.fmt.allocPrint(allocator, "dist/{s}", .{wheel_filename});
    errdefer allocator.free(wheel_path);

    // Extract stubs from the compiled module if enabled
    var stub_content: ?[]const u8 = null;
    defer if (stub_content) |sc| allocator.free(sc);

    if (generate_stubs) {
        std.debug.print("  Extracting type stubs from module...\n", .{});
        stub_content = symreader.extractStubs(allocator, build_result.module_path) catch |err| blk: {
            std.debug.print("  Warning: Could not extract stubs: {}\n", .{err});
            break :blk null;
        };

        if (stub_content) |_| {
            std.debug.print("  Including type stubs: {s}.pyi\n", .{config.name});
        } else {
            std.debug.print("  Note: No stubs found in module. Ensure your module uses pyoz.module().\n", .{});
        }
    }

    // Create the wheel (ZIP file)
    try createWheelZip(allocator, wheel_path, &config, &python, build_result.module_path, build_result.module_name, stub_content);

    std.debug.print("\nWheel created: {s}\n", .{wheel_path});
    std.debug.print("\nTo install locally: pip install {s}\n", .{wheel_path});
    std.debug.print("To publish: pyoz publish\n", .{});

    // Return owned path (caller must free)
    return wheel_path;
}

fn createWheelZip(
    allocator: std.mem.Allocator,
    wheel_path: []const u8,
    config: *const project.toml.PyProjectConfig,
    python: *const builder.PythonConfig,
    module_path: []const u8,
    module_name: []const u8,
    stub_content: ?[]const u8,
) !void {
    const cwd = std.fs.cwd();

    // Delete existing wheel file if present
    cwd.deleteFile(wheel_path) catch {};

    // Create ZIP writer for the wheel
    var z = try zip.ZipWriter.init(allocator, wheel_path);
    defer z.deinit();

    // Add the compiled module
    try z.addFileFromDisk(module_name, module_path);

    // Add the .pyi stub file if provided (from memory content)
    var stub_name: ?[]const u8 = null;
    defer if (stub_name) |sn| allocator.free(sn);

    if (stub_content) |sc| {
        stub_name = try std.fmt.allocPrint(allocator, "{s}.pyi", .{config.name});
        try z.addFile(stub_name.?, sc);
    }

    // Create dist-info directory name
    const dist_info_name = try std.fmt.allocPrint(allocator, "{s}-{s}.dist-info", .{ config.name, config.getVersion() });
    defer allocator.free(dist_info_name);

    // Create WHEEL file content with appropriate tag based on ABI3 mode
    const platform_tag = try getPlatformTag(allocator, config.getLinuxPlatformTag());
    defer if (builtin.os.tag == .macos) allocator.free(platform_tag);

    const wheel_content = if (config.getAbi3())
        // ABI3 mode: hardcoded cp38-abi3 tag
        try std.fmt.allocPrint(allocator,
            \\Wheel-Version: 1.0
            \\Generator: pyoz
            \\Root-Is-Purelib: false
            \\Tag: cp38-abi3-{s}
            \\
        , .{platform_tag})
    else
        // Non-ABI3 mode: use cpXY-cpXY tag format
        try std.fmt.allocPrint(allocator,
            \\Wheel-Version: 1.0
            \\Generator: pyoz
            \\Root-Is-Purelib: false
            \\Tag: cp{d}{d}-cp{d}{d}-{s}
            \\
        , .{ python.version_major, python.version_minor, python.version_major, python.version_minor, platform_tag });
    defer allocator.free(wheel_content);

    const wheel_file_path = try std.fmt.allocPrint(allocator, "{s}/WHEEL", .{dist_info_name});
    defer allocator.free(wheel_file_path);
    try z.addFile(wheel_file_path, wheel_content);

    // Try to read README.md for the long description
    const readme_content: ?[]const u8 = cwd.readFileAlloc(allocator, "README.md", 1024 * 1024) catch null;
    defer if (readme_content) |rc| allocator.free(rc);

    // Create METADATA file content
    const metadata_content = if (readme_content) |readme|
        try std.fmt.allocPrint(allocator,
            \\Metadata-Version: 2.1
            \\Name: {s}
            \\Version: {s}
            \\Summary: {s}
            \\Requires-Python: {s}
            \\Description-Content-Type: text/markdown
            \\
            \\{s}
        , .{ config.name, config.getVersion(), config.description, config.getPythonRequires(), readme })
    else
        try std.fmt.allocPrint(allocator,
            \\Metadata-Version: 2.1
            \\Name: {s}
            \\Version: {s}
            \\Summary: {s}
            \\Requires-Python: {s}
            \\
        , .{ config.name, config.getVersion(), config.description, config.getPythonRequires() });
    defer allocator.free(metadata_content);

    const metadata_file_path = try std.fmt.allocPrint(allocator, "{s}/METADATA", .{dist_info_name});
    defer allocator.free(metadata_file_path);
    try z.addFile(metadata_file_path, metadata_content);

    // Create RECORD file content (list of files with hashes)
    const record_content = if (stub_name) |sn|
        try std.fmt.allocPrint(allocator,
            \\{s},,
            \\{s},,
            \\{s}/WHEEL,,
            \\{s}/METADATA,,
            \\{s}/RECORD,,
            \\
        , .{ module_name, sn, dist_info_name, dist_info_name, dist_info_name })
    else
        try std.fmt.allocPrint(allocator,
            \\{s},,
            \\{s}/WHEEL,,
            \\{s}/METADATA,,
            \\{s}/RECORD,,
            \\
        , .{ module_name, dist_info_name, dist_info_name, dist_info_name });
    defer allocator.free(record_content);

    const record_file_path = try std.fmt.allocPrint(allocator, "{s}/RECORD", .{dist_info_name});
    defer allocator.free(record_file_path);
    try z.addFile(record_file_path, record_content);

    // Finalize the ZIP file
    try z.finish();
}

/// Get platform tag for wheel filename
/// If linux_platform_tag is provided (non-empty), use it for Linux builds.
/// Otherwise, use the default platform-specific tag.
/// For macOS, detects the actual OS version at runtime.
fn getPlatformTag(allocator: std.mem.Allocator, linux_platform_tag: []const u8) ![]const u8 {
    return switch (builtin.os.tag) {
        .linux => if (linux_platform_tag.len > 0)
            linux_platform_tag
        else switch (builtin.cpu.arch) {
            .x86_64 => "linux_x86_64",
            .aarch64 => "linux_aarch64",
            else => "linux_unknown",
        },
        .macos => try getMacOSPlatformTag(allocator),
        .windows => switch (builtin.cpu.arch) {
            .x86_64 => "win_amd64",
            .x86 => "win32",
            .aarch64 => "win_arm64",
            else => "win_unknown",
        },
        else => "unknown",
    };
}

/// Get macOS platform tag by detecting the actual OS version at runtime via Python
fn getMacOSPlatformTag(allocator: std.mem.Allocator) ![]const u8 {
    const arch_str = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        else => "unknown",
    };

    // Get macOS version using Python's platform module
    const python_cmd = builder.getPythonCommand();
    const result = builder.runCommand(allocator, &.{
        python_cmd, "-c", "import platform; print(platform.mac_ver()[0])",
    }) catch {
        // Fallback to safe defaults if detection fails
        return if (builtin.cpu.arch == .aarch64) "macosx_11_0_arm64" else "macosx_10_9_x86_64";
    };
    defer allocator.free(result);

    const version_str = std.mem.trim(u8, result, &std.ascii.whitespace);

    // Parse version (e.g., "14.5" or "13.2.1")
    var major: u32 = 10;
    var minor: u32 = 9;

    var parts = std.mem.splitScalar(u8, version_str, '.');
    if (parts.next()) |major_str| {
        major = std.fmt.parseInt(u32, major_str, 10) catch 10;
    }
    if (parts.next()) |minor_str| {
        minor = std.fmt.parseInt(u32, minor_str, 10) catch 9;
    }

    // Format: macosx_{major}_{minor}_{arch}
    return try std.fmt.allocPrint(allocator, "macosx_{d}_{d}_{s}", .{ major, minor, arch_str });
}

/// Publish wheel(s) to PyPI or TestPyPI
pub fn publish(allocator: std.mem.Allocator, test_pypi: bool) !void {
    const repo = if (test_pypi) pypi.Repository.testpypi else pypi.Repository.pypi;

    std.debug.print("Publishing to {s}...\n\n", .{repo.name});

    // Load project config
    var config = project.toml.loadPyProject(allocator) catch |err| {
        if (err == error.PyProjectNotFound) {
            std.debug.print("Error: pyproject.toml not found.\n", .{});
            return err;
        }
        return err;
    };
    defer config.deinit(allocator);

    // Get credentials
    const creds = pypi.getCredentials(allocator, repo) catch |err| {
        if (err == error.NoCredentials) return err;
        return err;
    };
    defer allocator.free(creds.username);
    defer allocator.free(creds.password);

    // Find wheel files in dist/
    const cwd = std.fs.cwd();
    var dist_dir = cwd.openDir("dist", .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: No dist/ directory. Run 'pyoz build' first.\n", .{});
            return error.NoDistDir;
        }
        return err;
    };
    defer dist_dir.close();

    // Collect wheel files
    var wheels = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (wheels.items) |w| allocator.free(w);
        wheels.deinit(allocator);
    }

    var iter = dist_dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".whl")) {
            const wheel_path = try std.fmt.allocPrint(allocator, "dist/{s}", .{entry.name});
            try wheels.append(allocator, wheel_path);
        }
    }

    if (wheels.items.len == 0) {
        std.debug.print("Error: No wheel files in dist/. Run 'pyoz build' first.\n", .{});
        return error.NoWheels;
    }

    std.debug.print("Found {d} wheel(s) to upload:\n", .{wheels.items.len});
    for (wheels.items) |w| {
        std.debug.print("  {s}\n", .{w});
    }
    std.debug.print("\n", .{});

    // Upload each wheel
    for (wheels.items) |wheel_path| {
        try pypi.uploadWheel(allocator, wheel_path, &config, repo, creds.username, creds.password);
    }

    std.debug.print("\nSuccessfully published to {s}!\n", .{repo.name});

    if (test_pypi) {
        std.debug.print("View at: https://test.pypi.org/project/{s}/\n", .{config.name});
        std.debug.print("Install with: pip install -i https://test.pypi.org/simple/ {s}\n", .{config.name});
    } else {
        std.debug.print("View at: https://pypi.org/project/{s}/\n", .{config.name});
        std.debug.print("Install with: pip install {s}\n", .{config.name});
    }
}
