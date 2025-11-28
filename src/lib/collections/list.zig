//! List types for Python interop
//!
//! Provides ListView for zero-copy access to Python lists and AllocatedSlice
//! for owning converted list data.

const std = @import("std");
const py = @import("../python.zig");
const PyObject = py.PyObject;

/// Zero-copy view of a Python list for use as a function parameter.
/// Provides iterator access without allocating memory.
/// Usage: fn process_list(items: ListView(i64)) void { ... }
///
/// Note: This type requires a Converter to be passed for type conversions.
/// Use the ListViewWithConverter function to create a view with a specific converter.
pub fn ListView(comptime T: type) type {
    return ListViewWithConverter(T, @import("../conversion.zig").Conversions);
}

/// ListView with explicit converter type - used internally
pub fn ListViewWithConverter(comptime T: type, comptime Conv: type) type {
    return struct {
        pub const _is_pyoz_list_view = true;

        py_list: *PyObject,

        const Self = @This();
        pub const ElementType = T;

        /// Get an element by index, returns null if conversion fails
        pub fn get(self: Self, index: usize) ?T {
            const idx: py.Py_ssize_t = @intCast(index);
            const py_item = py.PyList_GetItem(self.py_list, idx) orelse return null;
            return Conv.fromPy(T, py_item) catch null;
        }

        /// Get the number of items
        pub fn len(self: Self) usize {
            return @intCast(py.PyList_Size(self.py_list));
        }

        /// Check if the list is empty
        pub fn isEmpty(self: Self) bool {
            return self.len() == 0;
        }

        /// Iterator over elements
        pub fn iterator(self: Self) Iterator {
            return .{ .list = self.py_list, .index = 0, .length = self.len() };
        }

        pub const Iterator = struct {
            list: *PyObject,
            index: usize,
            length: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.length) return null;
                const idx: py.Py_ssize_t = @intCast(self.index);
                self.index += 1;
                const py_item = py.PyList_GetItem(self.list, idx) orelse return null;
                return Conv.fromPy(T, py_item) catch null;
            }

            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        /// Convert to an allocated slice (caller owns memory)
        /// Uses the provided allocator to allocate the slice
        pub fn toSlice(self: Self, allocator: std.mem.Allocator) ![]T {
            const length = self.len();
            const slice = try allocator.alloc(T, length);
            errdefer allocator.free(slice);

            for (0..length) |i| {
                slice[i] = self.get(i) orelse return error.ConversionFailed;
            }
            return slice;
        }
    };
}

/// Allocated slice from a Python list - owns its memory.
/// The slice is allocated using the provided allocator and must be freed by the caller.
/// Usage: fn process_numbers(numbers: AllocatedSlice(i64)) void { defer numbers.deinit(); ... }
pub fn AllocatedSlice(comptime T: type) type {
    return struct {
        items: []T,
        allocator: std.mem.Allocator,

        const Self = @This();
        pub const ElementType = T;

        pub fn deinit(self: Self) void {
            self.allocator.free(self.items);
        }

        pub fn len(self: Self) usize {
            return self.items.len;
        }

        pub fn get(self: Self, index: usize) T {
            return self.items[index];
        }

        pub fn slice(self: Self) []const T {
            return self.items;
        }
    };
}
