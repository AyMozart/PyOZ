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
        pub const _is_pyoz_iterator_view = true;

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

/// A simple iterator wrapper for returning a slice as a Python list.
/// All items are materialized eagerly when returned to Python.
///
/// Usage:
///   fn get_numbers() Iterator(i64) {
///       const items = [_]i64{ 1, 2, 3, 4, 5 };
///       return .{ .items = &items };
///   }
///
/// Note: This converts to a Python list, not a lazy iterator.
/// For lazy/on-demand iteration, use LazyIterator instead.
pub fn Iterator(comptime T: type) type {
    return struct {
        pub const _is_pyoz_iterator = true;

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
        pub const _is_pyoz_lazy_iterator = true;

        state: State,

        const Self = @This();
        pub const ElementType = T;
        pub const StateType = State;

        pub fn next(self: *Self) ?T {
            return self.state.next();
        }
    };
}

/// Generate a Python iterator wrapper type for LazyIterator
/// This creates a heap-allocated Python object that wraps the Zig state
pub fn LazyIteratorWrapper(comptime T: type, comptime State: type) type {
    const Conv = @import("../conversion.zig").Conversions;
    const StateSize = @sizeOf(State);
    const StateAlign = if (StateSize == 0) 1 else @alignOf(State);

    return struct {
        const Self = @This();

        /// The Python object wrapper that holds the Zig state
        pub const PyIterWrapper = extern struct {
            ob_base: py.PyObject,
            _state_storage: [StateSize]u8 align(StateAlign),

            pub fn getState(self: *PyIterWrapper) *State {
                return @ptrCast(@alignCast(&self._state_storage));
            }
        };

        /// tp_iter: return self (iterators are their own iterators)
        fn py_iter(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            if (self_obj) |obj| {
                py.Py_IncRef(obj);
                return obj;
            }
            return null;
        }

        /// tp_iternext: get next item or return null for StopIteration
        fn py_iternext(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const wrapper: *PyIterWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const state = wrapper.getState();

            if (state.next()) |value| {
                return Conv.toPy(T, value);
            } else {
                // Return null without setting an exception = StopIteration
                return null;
            }
        }

        /// tp_dealloc: free the object
        fn py_dealloc(self_obj: ?*py.PyObject) callconv(.c) void {
            const obj = self_obj orelse return;
            py.PyObject_Del(obj);
        }

        /// The Python type object for this iterator
        pub var type_object: py.PyTypeObject = makeTypeObject();

        fn makeTypeObject() py.PyTypeObject {
            var obj: py.PyTypeObject = std.mem.zeroes(py.PyTypeObject);

            // Basic setup - handle refcnt field difference across Python versions
            if (comptime @hasField(py.c.PyObject, "ob_refcnt")) {
                obj.ob_base.ob_base.ob_refcnt = 1;
            } else {
                const ob_ptr: *py.Py_ssize_t = @ptrCast(&obj.ob_base.ob_base);
                ob_ptr.* = 1;
            }

            obj.tp_name = "pyoz_iterator";
            obj.tp_basicsize = @sizeOf(PyIterWrapper);
            obj.tp_flags = py.Py_TPFLAGS_DEFAULT;
            obj.tp_doc = "PyOZ lazy iterator";
            obj.tp_dealloc = @ptrCast(&py_dealloc);
            obj.tp_iter = @ptrCast(&py_iter);
            obj.tp_iternext = @ptrCast(&py_iternext);

            return obj;
        }

        var type_ready: bool = false;

        /// Initialize the type (must be called before creating instances)
        pub fn ensureTypeReady() bool {
            if (type_ready) return true;
            if (py.PyType_Ready(&type_object) < 0) return false;
            type_ready = true;
            return true;
        }

        /// Create a new Python iterator from a LazyIterator value
        pub fn create(lazy_iter: LazyIterator(T, State)) ?*py.PyObject {
            if (!ensureTypeReady()) return null;

            const obj = py.PyObject_New(PyIterWrapper, &type_object) orelse return null;
            obj.getState().* = lazy_iter.state;
            return @ptrCast(obj);
        }
    };
}
