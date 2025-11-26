//! Path type for Python interop
//!
//! Provides Path type for working with Python pathlib.Path objects.

/// A path type for accepting/returning pathlib.Path objects
/// Internally stores the path as a string slice
pub const Path = struct {
    path: []const u8,

    pub fn init(path: []const u8) Path {
        return .{ .path = path };
    }
};
