const std = @import("std");

/// Minimal TOML parser - only parses what PyOZ needs from pyproject.toml
/// Not a full TOML implementation!
pub const PyProjectConfig = struct {
    // [project]
    name: []const u8 = "",
    version: []const u8 = "",
    description: []const u8 = "",
    python_requires: []const u8 = "",

    // [tool.pyoz]
    module_path: []const u8 = "",
    optimize: []const u8 = "",
    strip: bool = false,
    linux_platform_tag: []const u8 = "",
    abi3: bool = false,

    // Track which fields were allocated
    name_allocated: bool = false,
    version_allocated: bool = false,
    description_allocated: bool = false,
    python_requires_allocated: bool = false,
    module_path_allocated: bool = false,
    optimize_allocated: bool = false,
    linux_platform_tag_allocated: bool = false,

    pub fn deinit(self: *PyProjectConfig, allocator: std.mem.Allocator) void {
        if (self.name_allocated) allocator.free(self.name);
        if (self.version_allocated) allocator.free(self.version);
        if (self.description_allocated) allocator.free(self.description);
        if (self.python_requires_allocated) allocator.free(self.python_requires);
        if (self.module_path_allocated) allocator.free(self.module_path);
        if (self.optimize_allocated) allocator.free(self.optimize);
        if (self.linux_platform_tag_allocated) allocator.free(self.linux_platform_tag);
    }

    /// Get version with fallback to default
    pub fn getVersion(self: PyProjectConfig) []const u8 {
        return if (self.version.len > 0) self.version else "0.1.0";
    }

    /// Get python_requires with fallback to default
    pub fn getPythonRequires(self: PyProjectConfig) []const u8 {
        return if (self.python_requires.len > 0) self.python_requires else ">=3.8";
    }

    /// Get module_path with fallback to default
    pub fn getModulePath(self: PyProjectConfig) []const u8 {
        return if (self.module_path.len > 0) self.module_path else "src/lib.zig";
    }

    /// Get optimize (empty string means debug/unset)
    pub fn getOptimize(self: PyProjectConfig) []const u8 {
        return self.optimize;
    }

    /// Get linux platform tag (empty string means use default linux_* tag)
    pub fn getLinuxPlatformTag(self: PyProjectConfig) []const u8 {
        return self.linux_platform_tag;
    }

    /// Get ABI3 mode (hardcoded to Python 3.8 minimum)
    pub fn getAbi3(self: PyProjectConfig) bool {
        return self.abi3;
    }
};

const Section = enum {
    none,
    project,
    tool_pyoz,
    other,
};

pub fn parse(allocator: std.mem.Allocator, content: []const u8) !PyProjectConfig {
    var config = PyProjectConfig{};
    var current_section: Section = .none;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Skip empty lines and comments
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Section header
        if (trimmed[0] == '[') {
            if (std.mem.eql(u8, trimmed, "[project]")) {
                current_section = .project;
            } else if (std.mem.eql(u8, trimmed, "[tool.pyoz]")) {
                current_section = .tool_pyoz;
            } else {
                current_section = .other;
            }
            continue;
        }

        // Key = value
        const eq_pos = std.mem.indexOf(u8, trimmed, "=") orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq_pos], &std.ascii.whitespace);
        const value = stripQuotes(std.mem.trim(u8, trimmed[eq_pos + 1 ..], &std.ascii.whitespace));

        switch (current_section) {
            .project => {
                if (std.mem.eql(u8, key, "name")) {
                    config.name = try allocator.dupe(u8, value);
                    config.name_allocated = true;
                } else if (std.mem.eql(u8, key, "version")) {
                    config.version = try allocator.dupe(u8, value);
                    config.version_allocated = true;
                } else if (std.mem.eql(u8, key, "description")) {
                    config.description = try allocator.dupe(u8, value);
                    config.description_allocated = true;
                } else if (std.mem.eql(u8, key, "requires-python")) {
                    config.python_requires = try allocator.dupe(u8, value);
                    config.python_requires_allocated = true;
                }
            },
            .tool_pyoz => {
                if (std.mem.eql(u8, key, "module-path")) {
                    config.module_path = try allocator.dupe(u8, value);
                    config.module_path_allocated = true;
                } else if (std.mem.eql(u8, key, "optimize")) {
                    config.optimize = try allocator.dupe(u8, value);
                    config.optimize_allocated = true;
                } else if (std.mem.eql(u8, key, "strip")) {
                    config.strip = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "linux-platform-tag")) {
                    config.linux_platform_tag = try allocator.dupe(u8, value);
                    config.linux_platform_tag_allocated = true;
                } else if (std.mem.eql(u8, key, "abi3")) {
                    config.abi3 = std.mem.eql(u8, value, "true");
                }
            },
            else => {},
        }
    }

    if (config.name.len == 0) {
        return error.MissingProjectName;
    }

    return config;
}

fn stripQuotes(s: []const u8) []const u8 {
    if (s.len < 2) return s;
    if ((s[0] == '"' and s[s.len - 1] == '"') or
        (s[0] == '\'' and s[s.len - 1] == '\''))
    {
        return s[1 .. s.len - 1];
    }
    return s;
}

/// Load and parse pyproject.toml from the current directory
pub fn loadPyProject(allocator: std.mem.Allocator) !PyProjectConfig {
    const cwd = std.fs.cwd();
    const content = cwd.readFileAlloc(allocator, "pyproject.toml", 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            return error.PyProjectNotFound;
        }
        return err;
    };
    defer allocator.free(content);

    return parse(allocator, content);
}
