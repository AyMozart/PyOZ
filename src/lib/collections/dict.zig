//! Dict types for Python interop
//!
//! Provides DictView for zero-copy access to Python dicts and Dict for returning dicts.

const std = @import("std");
const py = @import("../python.zig");
const PyObject = py.PyObject;

/// A view into a Python dict that provides zero-copy access.
/// Use this as a function parameter type to receive Python dicts.
/// The view is only valid while the Python dict exists.
///
/// Note: This type requires a Converter to be passed for type conversions.
/// Use the DictViewWithConverter function to create a view with a specific converter.
pub fn DictView(comptime K: type, comptime V: type) type {
    return DictViewWithConverter(K, V, @import("../conversion.zig").Conversions);
}

/// DictView with explicit converter type - used internally
pub fn DictViewWithConverter(comptime K: type, comptime V: type, comptime Conv: type) type {
    return struct {
        pub const _is_pyoz_dict_view = true;

        py_dict: *PyObject,

        const Self = @This();

        /// Get a value by key, returns null if not found
        pub fn get(self: Self, key: K) ?V {
            // Convert key to Python
            const py_key = Conv.toPy(K, key) orelse return null;
            defer py.Py_DecRef(py_key);

            // Get item (borrowed reference)
            const py_val = py.PyDict_GetItem(self.py_dict, py_key) orelse return null;

            // Convert value
            return Conv.fromPy(V, py_val) catch null;
        }

        /// Check if key exists
        pub fn contains(self: Self, key: K) bool {
            const py_key = Conv.toPy(K, key) orelse return false;
            defer py.Py_DecRef(py_key);
            return py.PyDict_GetItem(self.py_dict, py_key) != null;
        }

        /// Get the number of items
        pub fn len(self: Self) usize {
            return @intCast(py.PyDict_Size(self.py_dict));
        }

        /// Iterator over keys
        pub fn keys(self: Self) KeyIterator {
            return .{ .dict = self.py_dict, .pos = 0 };
        }

        /// Iterator over key-value pairs
        pub fn iterator(self: Self) Iterator {
            return .{ .dict = self.py_dict, .pos = 0 };
        }

        pub const KeyIterator = struct {
            dict: *PyObject,
            pos: py.Py_ssize_t,

            pub fn next(self: *KeyIterator) ?K {
                var key: ?*PyObject = null;
                var value: ?*PyObject = null;
                if (py.PyDict_Next(self.dict, &self.pos, &key, &value) != 0) {
                    if (key) |k| {
                        return Conv.fromPy(K, k) catch null;
                    }
                }
                return null;
            }
        };

        pub const Iterator = struct {
            dict: *PyObject,
            pos: py.Py_ssize_t,

            pub fn next(self: *Iterator) ?struct { key: K, value: V } {
                var key: ?*PyObject = null;
                var value: ?*PyObject = null;
                if (py.PyDict_Next(self.dict, &self.pos, &key, &value) != 0) {
                    if (key != null and value != null) {
                        const k = Conv.fromPy(K, key.?) catch return null;
                        const v = Conv.fromPy(V, value.?) catch return null;
                        return .{ .key = k, .value = v };
                    }
                }
                return null;
            }
        };
    };
}

/// Marker type to indicate a function returns a dict
/// Usage: fn myFunc() Dict([]const u8, i64) { ... }
pub fn Dict(comptime K: type, comptime V: type) type {
    return struct {
        pub const _is_pyoz_dict = true;

        entries: []const Entry,

        pub const Entry = struct {
            key: K,
            value: V,
        };

        pub const KeyType = K;
        pub const ValueType = V;
    };
}
