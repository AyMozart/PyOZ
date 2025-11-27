//! Iterator types for Python interop
//!
//! Provides IteratorView for receiving any Python iterator as a function argument
//! and Iterator for returning iterators from Zig functions.

const std = @import("std");
const py = @import("../python.zig");
const PyObject = py.PyObject;

/// Zero-copy view of a Python iterator for use as a function parameter.
/// Can receive any Python iterable (list, set, dict, generator, etc.)
/// The iterator is consumed as you iterate - it cannot be reset.
///
/// Usage:
///   fn process_items(items: IteratorView(i64)) i64 {
///       var sum: i64 = 0;
///       while (items.next()) |value| {
///           sum += value;
///       }
///       return sum;
///   }
///
/// Note: This type requires a Converter to be passed for type conversions.
/// Use IteratorViewWithConverter for explicit converter specification.
pub fn IteratorView(comptime T: type) type {
    return IteratorViewWithConverter(T, @import("../conversion.zig").Conversions);
}

/// IteratorView with explicit converter type - used internally
pub fn IteratorViewWithConverter(comptime T: type, comptime Conv: type) type {
    return struct {
        const _is_pyoz_iterator = true;

        py_iter: *PyObject,

        const Self = @This();
        pub const ElementType = T;

        /// Get the next item from the iterator.
        /// Returns null when the iterator is exhausted.
        pub fn next(self: *Self) ?T {
            const py_item = py.PyIter_Next(self.py_iter) orelse {
                // Check if this was StopIteration or an actual error
                if (py.PyErr_Occurred() != null) {
                    // Real error occurred - clear it and return null
                    py.PyErr_Clear();
                }
                return null;
            };
            defer py.Py_DecRef(py_item);
            return Conv.fromPy(T, py_item) catch null;
        }

        /// Collect all remaining items into an allocated slice.
        /// Caller owns the returned memory and must free it.
        pub fn collect(self: *Self, allocator: std.mem.Allocator) ![]T {
            var items = std.ArrayList(T).init(allocator);
            errdefer items.deinit();

            while (self.next()) |item| {
                try items.append(item);
            }

            return items.toOwnedSlice();
        }

        /// Count remaining items (consumes the iterator)
        pub fn count(self: *Self) usize {
            var n: usize = 0;
            while (self.next()) |_| {
                n += 1;
            }
            return n;
        }

        /// Check if iterator has any remaining items.
        /// Note: This consumes one item if available, so use with caution.
        /// Returns the first item if available, null otherwise.
        pub fn peek(self: *Self) ?T {
            return self.next();
        }

        /// Apply a function to each item (consumes the iterator)
        pub fn forEach(self: *Self, func: *const fn (T) void) void {
            while (self.next()) |item| {
                func(item);
            }
        }

        /// Find the first item matching a predicate (consumes iterator until found)
        pub fn find(self: *Self, predicate: *const fn (T) bool) ?T {
            while (self.next()) |item| {
                if (predicate(item)) {
                    return item;
                }
            }
            return null;
        }

        /// Check if any item matches the predicate (consumes iterator until found)
        pub fn any(self: *Self, predicate: *const fn (T) bool) bool {
            while (self.next()) |item| {
                if (predicate(item)) {
                    return true;
                }
            }
            return false;
        }

        /// Check if all items match the predicate (consumes entire iterator)
        pub fn all(self: *Self, predicate: *const fn (T) bool) bool {
            while (self.next()) |item| {
                if (!predicate(item)) {
                    return false;
                }
            }
            return true;
        }

        /// Release the iterator reference.
        /// Called automatically when the function returns, but can be called
        /// explicitly if you want to release early.
        pub fn deinit(self: *Self) void {
            py.Py_DecRef(self.py_iter);
        }
    };
}

/// A Zig iterator adapter that can be returned to Python.
/// Wraps a Zig iterator (any type with a `next() ?T` method) and converts
/// it to a Python iterator object.
///
/// Usage in a function that returns an iterator:
///   fn range(start: i64, end: i64) Iterator(i64) {
///       return .{ .state = .{ .current = start, .end = end } };
///   }
///
/// The Iterator type must define:
///   - ElementType: the type of elements yielded
///   - State: internal state type
///   - next(*State) ?ElementType: yields next element or null when done
pub fn Iterator(comptime T: type) type {
    return struct {
        items: []const T,

        pub const ElementType = T;
    };
}

/// A lazy iterator that generates values on-demand.
/// This is used when you want to return a generator-like iterator to Python.
///
/// Usage:
///   const RangeState = struct {
///       current: i64,
///       end: i64,
///
///       pub fn next(self: *@This()) ?i64 {
///           if (self.current >= self.end) return null;
///           const val = self.current;
///           self.current += 1;
///           return val;
///       }
///   };
///
///   fn make_range(start: i64, end: i64) LazyIterator(i64, RangeState) {
///       return .{ .state = .{ .current = start, .end = end } };
///   }
pub fn LazyIterator(comptime T: type, comptime State: type) type {
    return struct {
        state: State,

        const Self = @This();
        pub const ElementType = T;
        pub const StateType = State;
        pub const is_lazy_iterator = true;

        pub fn next(self: *Self) ?T {
            return self.state.next();
        }
    };
}
