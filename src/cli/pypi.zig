const std = @import("std");
const builtin = @import("builtin");
const project = @import("project.zig");

/// PyPI repository configuration
pub const Repository = struct {
    name: []const u8,
    url: []const u8,

    pub const pypi = Repository{
        .name = "PyPI",
        .url = "https://upload.pypi.org/legacy/",
    };

    pub const testpypi = Repository{
        .name = "TestPyPI",
        .url = "https://test.pypi.org/legacy/",
    };
};

/// Upload a wheel file to PyPI using native Zig HTTP client
pub fn uploadWheel(
    allocator: std.mem.Allocator,
    wheel_path: []const u8,
    config: *const project.toml.PyProjectConfig,
    repo: Repository,
    username: []const u8,
    password: []const u8,
) !void {
    const basename = std.fs.path.basename(wheel_path);
    std.debug.print("Uploading {s} to {s}...\n", .{ basename, repo.name });

    // Read the wheel file
    const cwd = std.fs.cwd();
    const wheel_data = try cwd.readFileAlloc(allocator, wheel_path, 500 * 1024 * 1024);
    defer allocator.free(wheel_data);

    // Calculate SHA256 hash
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(wheel_data, &hash, .{});

    var hash_hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hash_hex, "{x}", .{hash}) catch unreachable;

    // Extract Python version tag from wheel filename
    const pyversion = extractPythonVersion(basename) orelse "py3";

    // Build multipart form data
    const boundary = "----PyOZUploadBoundary7MA4YWxkTrZu0gW";

    var body = std.ArrayListUnmanaged(u8){};
    defer body.deinit(allocator);

    // Add form fields
    try addFormField(allocator, &body, boundary, ":action", "file_upload");
    try addFormField(allocator, &body, boundary, "protocol_version", "1");
    try addFormField(allocator, &body, boundary, "filetype", "bdist_wheel");
    try addFormField(allocator, &body, boundary, "pyversion", pyversion);
    try addFormField(allocator, &body, boundary, "sha256_digest", &hash_hex);
    try addFormField(allocator, &body, boundary, "metadata_version", "2.1");
    try addFormField(allocator, &body, boundary, "name", config.name);
    try addFormField(allocator, &body, boundary, "version", config.getVersion());
    if (config.description.len > 0) {
        try addFormField(allocator, &body, boundary, "summary", config.description);
    }
    try addFormField(allocator, &body, boundary, "requires_python", config.getPythonRequires());

    // Add the wheel file
    try addFormFile(allocator, &body, boundary, "content", basename, wheel_data);

    // Close the multipart form
    try body.appendSlice(allocator, "--");
    try body.appendSlice(allocator, boundary);
    try body.appendSlice(allocator, "--\r\n");

    // Create Basic Auth header
    const auth_input = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ username, password });
    defer allocator.free(auth_input);

    const auth_encoded = try base64Encode(allocator, auth_input);
    defer allocator.free(auth_encoded);

    const auth_header = try std.fmt.allocPrint(allocator, "Basic {s}", .{auth_encoded});
    defer allocator.free(auth_header);

    const content_type = try std.fmt.allocPrint(allocator, "multipart/form-data; boundary={s}", .{boundary});
    defer allocator.free(content_type);

    // Make HTTP request
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = repo.url },
        .method = .POST,
        .headers = .{
            .content_type = .{ .override = content_type },
            .authorization = .{ .override = auth_header },
        },
        .payload = body.items,
    }) catch |err| {
        std.debug.print("HTTP request failed: {s}\n", .{@errorName(err)});
        return error.NetworkError;
    };

    // Check response status
    const status_code = @intFromEnum(result.status);

    if (status_code >= 200 and status_code < 300) {
        std.debug.print("Upload successful!\n", .{});
    } else if (status_code == 400) {
        std.debug.print("Upload failed: Bad request\n", .{});
        std.debug.print("This usually means the version already exists on {s}.\n", .{repo.name});
        std.debug.print("Try incrementing the version in pyproject.toml.\n", .{});
        return error.BadRequest;
    } else if (status_code == 401 or status_code == 403) {
        std.debug.print("Upload failed: Authentication failed (HTTP {d})\n", .{status_code});
        std.debug.print("Make sure you're using an API token with username '__token__'\n", .{});
        return error.AuthFailed;
    } else {
        std.debug.print("Upload failed with HTTP status {d}\n", .{status_code});
        return error.UploadFailed;
    }
}

fn extractPythonVersion(wheel_filename: []const u8) ?[]const u8 {
    // Format: {name}-{version}-{python}-{abi}-{platform}.whl
    var parts = std.mem.splitScalar(u8, wheel_filename, '-');
    _ = parts.next(); // name
    _ = parts.next(); // version
    return parts.next(); // python tag
}

fn addFormField(allocator: std.mem.Allocator, body: *std.ArrayListUnmanaged(u8), boundary: []const u8, name: []const u8, value: []const u8) !void {
    try body.appendSlice(allocator, "--");
    try body.appendSlice(allocator, boundary);
    try body.appendSlice(allocator, "\r\n");
    try body.appendSlice(allocator, "Content-Disposition: form-data; name=\"");
    try body.appendSlice(allocator, name);
    try body.appendSlice(allocator, "\"\r\n\r\n");
    try body.appendSlice(allocator, value);
    try body.appendSlice(allocator, "\r\n");
}

fn addFormFile(allocator: std.mem.Allocator, body: *std.ArrayListUnmanaged(u8), boundary: []const u8, name: []const u8, filename: []const u8, data: []const u8) !void {
    try body.appendSlice(allocator, "--");
    try body.appendSlice(allocator, boundary);
    try body.appendSlice(allocator, "\r\n");
    try body.appendSlice(allocator, "Content-Disposition: form-data; name=\"");
    try body.appendSlice(allocator, name);
    try body.appendSlice(allocator, "\"; filename=\"");
    try body.appendSlice(allocator, filename);
    try body.appendSlice(allocator, "\"\r\n");
    try body.appendSlice(allocator, "Content-Type: application/octet-stream\r\n\r\n");
    try body.appendSlice(allocator, data);
    try body.appendSlice(allocator, "\r\n");
}

fn base64Encode(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    const encoder = std.base64.standard.Encoder;
    const size = encoder.calcSize(input.len);
    const buf = try allocator.alloc(u8, size);
    _ = encoder.encode(buf, input);
    return buf;
}

/// Get API token from environment or show instructions
pub fn getCredentials(allocator: std.mem.Allocator, repo: Repository) !struct { username: []const u8, password: []const u8 } {
    // Try environment variables first
    const env_token = std.process.getEnvVarOwned(allocator, "PYPI_TOKEN") catch |err| blk: {
        if (err == error.EnvironmentVariableNotFound) break :blk null;
        return err;
    };

    if (env_token) |token| {
        return .{ .username = try allocator.dupe(u8, "__token__"), .password = token };
    }

    // Try TestPyPI specific env var
    if (std.mem.eql(u8, repo.name, "TestPyPI")) {
        const test_token = std.process.getEnvVarOwned(allocator, "TEST_PYPI_TOKEN") catch |err| blk: {
            if (err == error.EnvironmentVariableNotFound) break :blk null;
            return err;
        };

        if (test_token) |token| {
            return .{ .username = try allocator.dupe(u8, "__token__"), .password = token };
        }
    }

    // No token found - provide instructions
    std.debug.print("\nNo API token found.\n\n", .{});

    if (std.mem.eql(u8, repo.name, "TestPyPI")) {
        std.debug.print("To publish to TestPyPI:\n", .{});
        std.debug.print("  1. Create an account at https://test.pypi.org/\n", .{});
        std.debug.print("  2. Generate a token at https://test.pypi.org/manage/account/token/\n", .{});
        std.debug.print("  3. Set: export TEST_PYPI_TOKEN='pypi-...'\n", .{});
    } else {
        std.debug.print("To publish to PyPI:\n", .{});
        std.debug.print("  1. Create an account at https://pypi.org/\n", .{});
        std.debug.print("  2. Generate a token at https://pypi.org/manage/account/token/\n", .{});
        std.debug.print("  3. Set: export PYPI_TOKEN='pypi-...'\n", .{});
    }

    return error.NoCredentials;
}
