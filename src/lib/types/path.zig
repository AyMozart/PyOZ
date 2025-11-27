//! Path type for Python interop
//!
//! Provides Path type for working with Python pathlib.Path objects.

const py = @import("../python.zig");

/// A path type for accepting/returning pathlib.Path objects
/// Internally stores the path as a string slice plus a reference to the
/// Python string object that owns the memory.
pub const Path = struct {
    const _is_pyoz_path = true;

    path: []const u8,
    /// The Python string object that owns the path memory (may be null for literals)
    _py_str: ?*py.PyObject = null,

    pub fn init(path: []const u8) Path {
        return .{ .path = path, ._py_str = null };
    }

    /// Create a Path from a Python object, keeping a reference to the string
    pub fn fromPyObject(str_obj: *py.PyObject, path: []const u8) Path {
        return .{ .path = path, ._py_str = str_obj };
    }

    /// Release the Python string reference (called automatically after function returns)
    pub fn deinit(self: *Path) void {
        if (self._py_str) |str_obj| {
            py.Py_DecRef(str_obj);
            self._py_str = null;
        }
    }
};
