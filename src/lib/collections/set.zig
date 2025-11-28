//! Set types for Python interop
//!
//! Provides SetView for zero-copy access to Python sets and Set/FrozenSet
//! for returning sets.

const std = @import("std");
const py = @import("../python.zig");
const PyObject = py.PyObject;

/// Zero-copy view of a Python set for use as a function parameter.
/// Provides iterator access without allocating memory.
/// Usage: fn process_set(items: SetView(i64)) void { ... }
///
/// Note: This type requires a Converter to be passed for type conversions.
/// Use the SetViewWithConverter function to create a view with a specific converter.
pub fn SetView(comptime T: type) type {
    return SetViewWithConverter(T, @import("../conversion.zig").Conversions);
}

/// SetView with explicit converter type - used internally
pub fn SetViewWithConverter(comptime T: type, comptime Conv: type) type {
    return struct {
        pub const _is_pyoz_set_view = true;

        py_set: *PyObject,

        const Self = @This();
        pub const ElementType = T;

        /// Get the number of items in the set
        pub fn len(self: Self) usize {
            return @intCast(py.PySet_Size(self.py_set));
        }

        /// Check if the set is empty
        pub fn isEmpty(self: Self) bool {
            return self.len() == 0;
        }

        /// Check if the set contains a value
        pub fn contains(self: Self, value: T) bool {
            const py_val = Conv.toPy(T, value) orelse return false;
            defer py.Py_DecRef(py_val);
            return py.PySet_Contains(self.py_set, py_val) == 1;
        }

        /// Iterator over set elements using Python's native iterator protocol.
        /// This is more efficient than creating a temporary list copy.
        pub fn iterator(self: Self) Iterator {
            return .{
                .py_iter = py.PyObject_GetIter(self.py_set),
            };
        }

        pub const Iterator = struct {
            py_iter: ?*PyObject,

            pub fn next(self: *Iterator) ?T {
                const iter = self.py_iter orelse return null;
                const py_item = py.PyIter_Next(iter) orelse return null;
                defer py.Py_DecRef(py_item);
                return Conv.fromPy(T, py_item) catch null;
            }

            pub fn deinit(self: *Iterator) void {
                if (self.py_iter) |iter| {
                    py.Py_DecRef(iter);
                    self.py_iter = null;
                }
            }
        };
    };
}

/// Marker type to indicate a function returns a set
/// Usage: fn myFunc() Set(i64) { ... }
pub fn Set(comptime T: type) type {
    return struct {
        pub const _is_pyoz_set = true;

        items: []const T,

        pub const ElementType = T;
    };
}

/// Marker type for frozen set returns
pub fn FrozenSet(comptime T: type) type {
    return struct {
        pub const _is_pyoz_frozenset = true;

        items: []const T,

        pub const ElementType = T;
    };
}
