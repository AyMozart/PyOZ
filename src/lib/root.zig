//! PyOZ - Python bindings for Zig (like PyO3 for Rust)
//!
//! Write pure Zig functions and structs, PyOZ handles all the Python integration automatically.
//!
//! ## Example Usage - Functions
//!
//! ```zig
//! const pyoz = @import("pyoz");
//!
//! fn add(a: i64, b: i64) i64 {
//!     return a + b;
//! }
//!
//! const MyModule = pyoz.module(.{
//!     .name = "mymodule",
//!     .funcs = &.{ pyoz.func("add", add, "Add two numbers") },
//! });
//!
//! pub export fn PyInit_mymodule() ?*pyoz.PyObject {
//!     return MyModule.init();
//! }
//! ```
//!
//! ## Example Usage - Classes
//!
//! ```zig
//! const Point = struct {
//!     x: f64,
//!     y: f64,
//!
//!     pub fn distance(self: *const Point, other: *const Point) f64 {
//!         const dx = self.x - other.x;
//!         const dy = self.y - other.y;
//!         return @sqrt(dx * dx + dy * dy);
//!     }
//! };
//!
//! const MyModule = pyoz.module(.{
//!     .name = "mymodule",
//!     .classes = &.{ pyoz.class("Point", Point) },
//! });
//! ```

const std = @import("std");

// Version information - injected by build.zig as a module
pub const version = @import("version");
pub const py = @import("python.zig");
pub const class_mod = @import("class.zig");
pub const module_mod = @import("module.zig");

pub const PyObject = py.PyObject;
pub const PyMethodDef = py.PyMethodDef;
pub const PyModuleDef = py.PyModuleDef;
pub const PyTypeObject = py.PyTypeObject;
pub const Py_ssize_t = py.Py_ssize_t;

// ============================================================================
// Complex Number Support
// ============================================================================

/// A complex number type for use with __complex__ method
/// Return this from your __complex__ method to convert to Python complex
pub const Complex = struct {
    real: f64,
    imag: f64,

    pub fn init(real: f64, imag: f64) Complex {
        return .{ .real = real, .imag = imag };
    }
};

// ============================================================================
// DateTime Types
// ============================================================================

/// Initialize the datetime API - call this in module init if using datetime types
pub fn initDatetime() bool {
    return py.PyDateTime_Import();
}

/// A date type (year, month, day)
pub const Date = struct {
    year: i32,
    month: u8,
    day: u8,

    pub fn init(year: i32, month: u8, day: u8) Date {
        return .{ .year = year, .month = month, .day = day };
    }
};

/// A time type (hour, minute, second, microsecond)
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,

    pub fn init(hour: u8, minute: u8, second: u8) Time {
        return .{ .hour = hour, .minute = minute, .second = second, .microsecond = 0 };
    }

    pub fn initWithMicrosecond(hour: u8, minute: u8, second: u8, microsecond: u32) Time {
        return .{ .hour = hour, .minute = minute, .second = second, .microsecond = microsecond };
    }
};

/// A datetime type (date + time)
pub const DateTime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,

    pub fn init(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) DateTime {
        return .{ .year = year, .month = month, .day = day, .hour = hour, .minute = minute, .second = second, .microsecond = 0 };
    }

    pub fn initWithMicrosecond(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8, microsecond: u32) DateTime {
        return .{ .year = year, .month = month, .day = day, .hour = hour, .minute = minute, .second = second, .microsecond = microsecond };
    }

    pub fn date(self: DateTime) Date {
        return .{ .year = self.year, .month = self.month, .day = self.day };
    }

    pub fn time(self: DateTime) Time {
        return .{ .hour = self.hour, .minute = self.minute, .second = self.second, .microsecond = self.microsecond };
    }
};

/// A timedelta type (duration)
pub const TimeDelta = struct {
    days: i32,
    seconds: i32,
    microseconds: i32,

    pub fn init(days: i32, seconds: i32, microseconds: i32) TimeDelta {
        return .{ .days = days, .seconds = seconds, .microseconds = microseconds };
    }

    /// Create from total seconds
    pub fn fromSeconds(total_seconds: i64) TimeDelta {
        const days: i32 = @intCast(@divFloor(total_seconds, 86400));
        const remaining: i32 = @intCast(@mod(total_seconds, 86400));
        return .{ .days = days, .seconds = remaining, .microseconds = 0 };
    }

    /// Get total seconds
    pub fn totalSeconds(self: TimeDelta) i64 {
        return @as(i64, self.days) * 86400 + @as(i64, self.seconds);
    }
};

// ============================================================================
// Bytes Types
// ============================================================================

/// A bytes type for accepting Python bytes
pub const Bytes = struct {
    data: []const u8,
};

/// A bytearray type for accepting Python bytearray (mutable)
pub const ByteArray = struct {
    data: []u8,
};

// ============================================================================
// Path Type
// ============================================================================

/// A path type for accepting/returning pathlib.Path objects
/// Internally stores the path as a string slice
pub const Path = struct {
    path: []const u8,

    pub fn init(path: []const u8) Path {
        return .{ .path = path };
    }
};

// ============================================================================
// Decimal Type
// ============================================================================

/// A decimal type for accepting/returning decimal.Decimal objects
/// Stores the decimal as a string representation for exact precision
/// Usage:
///   fn process_money(amount: pyoz.Decimal) pyoz.Decimal {
///       // Parse and manipulate as needed
///       return pyoz.Decimal.init("99.99");
///   }
pub const Decimal = struct {
    /// String representation of the decimal value
    value: []const u8,

    /// Create a Decimal from a string
    pub fn init(value: []const u8) Decimal {
        return .{ .value = value };
    }

    /// Parse as f64 (may lose precision - use with caution)
    pub fn toFloat(self: Decimal) ?f64 {
        return std.fmt.parseFloat(f64, self.value) catch null;
    }

    /// Parse as i64 (truncates decimal part)
    pub fn toInt(self: Decimal) ?i64 {
        // Find decimal point and parse integer part
        for (self.value, 0..) |c, i| {
            if (c == '.') {
                return std.fmt.parseInt(i64, self.value[0..i], 10) catch null;
            }
        }
        return std.fmt.parseInt(i64, self.value, 10) catch null;
    }
};

// Cached decimal module and class
var decimal_module: ?*PyObject = null;
var decimal_class: ?*PyObject = null;

/// Initialize the decimal module - call this in module init if using Decimal type
pub fn initDecimal() bool {
    if (decimal_module != null) return true;

    decimal_module = py.PyImport_ImportModule("decimal");
    if (decimal_module == null) return false;

    decimal_class = py.PyObject_GetAttrString(decimal_module.?, "Decimal");
    if (decimal_class == null) {
        py.Py_DecRef(decimal_module.?);
        decimal_module = null;
        return false;
    }

    return true;
}

/// Check if an object is a decimal.Decimal instance
pub fn PyDecimal_Check(obj: *PyObject) bool {
    if (decimal_class == null) {
        if (!initDecimal()) return false;
    }
    return py.PyObject_IsInstance(obj, decimal_class.?) == 1;
}

/// Create a Python decimal.Decimal from a string
pub fn PyDecimal_FromString(value: []const u8) ?*PyObject {
    if (decimal_class == null) {
        if (!initDecimal()) return null;
    }

    const py_str = py.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len)) orelse return null;
    defer py.Py_DecRef(py_str);

    const args = py.PyTuple_New(1) orelse return null;
    defer py.Py_DecRef(args);

    // PyTuple_SetItem steals reference, so we need to incref
    py.Py_IncRef(py_str);
    if (py.PyTuple_SetItem(args, 0, py_str) < 0) return null;

    return py.PyObject_Call(decimal_class.?, args, null);
}

/// Get string representation of a Python decimal.Decimal
pub fn PyDecimal_AsString(obj: *PyObject) ?[]const u8 {
    const str_obj = py.PyObject_Str(obj) orelse return null;
    defer py.Py_DecRef(str_obj);

    var size: py.Py_ssize_t = 0;
    const ptr = py.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return null;
    return ptr[0..@intCast(size)];
}

// ============================================================================
// GC Support Types
// ============================================================================

/// Visitor for GC traversal - use in __traverse__ to visit PyObject references
/// Usage in __traverse__:
///   pub fn __traverse__(self: *MyClass, visitor: pyoz.GCVisitor) c_int {
///       var ret = visitor.call(self.some_py_object);
///       if (ret != 0) return ret;
///       return 0;
///   }
pub const GCVisitor = struct {
    visit: *const fn (?*PyObject, ?*anyopaque) callconv(.c) c_int,
    arg: ?*anyopaque,

    /// Visit a PyObject reference - call this for each Python object your class holds
    pub fn call(self: GCVisitor, obj: ?*PyObject) c_int {
        if (obj) |o| {
            return self.visit(o, self.arg);
        }
        return 0;
    }
};

// ============================================================================
// Exception Catching Support
// ============================================================================

/// Represents a caught Python exception
pub const PythonException = struct {
    exc_type: ?*PyObject,
    exc_value: ?*PyObject,
    exc_traceback: ?*PyObject,

    /// Get the exception type (e.g., ValueError, TypeError)
    pub fn getType(self: PythonException) ?*PyObject {
        return self.exc_type;
    }

    /// Get the exception value/message
    pub fn getValue(self: PythonException) ?*PyObject {
        return self.exc_value;
    }

    /// Get the exception traceback
    pub fn getTraceback(self: PythonException) ?*PyObject {
        return self.exc_traceback;
    }

    /// Check if this exception matches a specific type
    pub fn matches(self: PythonException, exc_type: *PyObject) bool {
        return py.PyErr_GivenExceptionMatches(self.exc_type, exc_type);
    }

    /// Check if this is a ValueError
    pub fn isValueError(self: PythonException) bool {
        return self.matches(py.PyExc_ValueError());
    }

    /// Check if this is a TypeError
    pub fn isTypeError(self: PythonException) bool {
        return self.matches(py.PyExc_TypeError());
    }

    /// Check if this is a KeyError
    pub fn isKeyError(self: PythonException) bool {
        return self.matches(py.PyExc_KeyError());
    }

    /// Check if this is an IndexError
    pub fn isIndexError(self: PythonException) bool {
        return self.matches(py.PyExc_IndexError());
    }

    /// Check if this is a RuntimeError
    pub fn isRuntimeError(self: PythonException) bool {
        return self.matches(py.PyExc_RuntimeError());
    }

    /// Check if this is a StopIteration
    pub fn isStopIteration(self: PythonException) bool {
        return self.matches(py.PyExc_StopIteration());
    }

    /// Check if this is a ZeroDivisionError
    pub fn isZeroDivisionError(self: PythonException) bool {
        return self.matches(py.PyExc_ZeroDivisionError());
    }

    /// Check if this is an AttributeError
    pub fn isAttributeError(self: PythonException) bool {
        return self.matches(py.PyExc_AttributeError());
    }

    /// Get the string representation of the exception value
    pub fn getMessage(self: PythonException) ?[]const u8 {
        if (self.exc_value) |val| {
            const str_obj = py.PyObject_Str(val) orelse return null;
            defer py.Py_DecRef(str_obj);
            return py.PyUnicode_AsUTF8(str_obj);
        }
        return null;
    }

    /// Re-raise this exception (restore it to Python's error state)
    pub fn reraise(self: PythonException) void {
        // Restore takes ownership, so we incref first if we want to keep our references
        if (self.exc_type) |t| py.Py_IncRef(t);
        if (self.exc_value) |v| py.Py_IncRef(v);
        if (self.exc_traceback) |tb| py.Py_IncRef(tb);
        py.PyErr_Restore(self.exc_type, self.exc_value, self.exc_traceback);
    }

    /// Release the exception references (call when you've handled the exception)
    pub fn deinit(self: *PythonException) void {
        if (self.exc_type) |t| py.Py_DecRef(t);
        if (self.exc_value) |v| py.Py_DecRef(v);
        if (self.exc_traceback) |tb| py.Py_DecRef(tb);
        self.exc_type = null;
        self.exc_value = null;
        self.exc_traceback = null;
    }
};

/// Catch the current Python exception if one is set
/// Returns null if no exception is pending
/// Usage:
///   if (catchException()) |*exc| {
///       defer exc.deinit();
///       if (exc.isValueError()) { ... }
///   }
pub fn catchException() ?PythonException {
    if (py.PyErr_Occurred() == null) {
        return null;
    }

    var exc = PythonException{
        .exc_type = null,
        .exc_value = null,
        .exc_traceback = null,
    };

    py.PyErr_Fetch(&exc.exc_type, &exc.exc_value, &exc.exc_traceback);
    py.PyErr_NormalizeException(&exc.exc_type, &exc.exc_value, &exc.exc_traceback);

    return exc;
}

/// Check if an exception is pending without clearing it
pub fn exceptionPending() bool {
    return py.PyErr_Occurred() != null;
}

/// Clear any pending exception
pub fn clearException() void {
    py.PyErr_Clear();
}

/// Raise a Python exception with a message
pub fn raiseException(exc_type: *PyObject, message: [*:0]const u8) void {
    py.PyErr_SetString(exc_type, message);
}

/// Raise a ValueError with a message
pub fn raiseValueError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_ValueError(), message);
}

/// Raise a TypeError with a message
pub fn raiseTypeError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_TypeError(), message);
}

/// Raise a RuntimeError with a message
pub fn raiseRuntimeError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_RuntimeError(), message);
}

/// Raise a KeyError with a message
pub fn raiseKeyError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_KeyError(), message);
}

/// Raise an IndexError with a message
pub fn raiseIndexError(message: [*:0]const u8) void {
    py.PyErr_SetString(py.PyExc_IndexError(), message);
}

/// Buffer info struct for implementing the buffer protocol
/// Return this from your __buffer__ method to expose memory to Python/numpy
pub const BufferInfo = struct {
    ptr: [*]u8,
    len: usize,
    readonly: bool = false,
    format: ?[*:0]u8 = null, // e.g., "d" for f64, "l" for i64, "B" for u8
    itemsize: usize = 1,
    ndim: usize = 1,
    shape: ?[*]Py_ssize_t = null,
    strides: ?[*]Py_ssize_t = null,
};

// ============================================================================
// Dict Support
// ============================================================================

/// A view into a Python dict that provides zero-copy access.
/// Use this as a function parameter type to receive Python dicts.
/// The view is only valid while the Python dict exists.
pub fn DictView(comptime K: type, comptime V: type) type {
    return struct {
        py_dict: *PyObject,

        const Self = @This();

        /// Get a value by key, returns null if not found
        pub fn get(self: Self, key: K) ?V {
            // Convert key to Python
            const py_key = Conversions.toPy(K, key) orelse return null;
            defer py.Py_DecRef(py_key);

            // Get item (borrowed reference)
            const py_val = py.PyDict_GetItem(self.py_dict, py_key) orelse return null;

            // Convert value
            return Conversions.fromPy(V, py_val) catch null;
        }

        /// Check if key exists
        pub fn contains(self: Self, key: K) bool {
            const py_key = Conversions.toPy(K, key) orelse return false;
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
                        return Conversions.fromPy(K, k) catch null;
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
                        const k = Conversions.fromPy(K, key.?) catch return null;
                        const v = Conversions.fromPy(V, value.?) catch return null;
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
        entries: []const Entry,

        pub const Entry = struct {
            key: K,
            value: V,
        };

        pub const KeyType = K;
        pub const ValueType = V;
    };
}

// ============================================================================
// List Input - Zero-copy list access and allocated slices
// ============================================================================

/// Zero-copy view of a Python list for use as a function parameter.
/// Provides iterator access without allocating memory.
/// Usage: fn process_list(items: ListView(i64)) void { ... }
pub fn ListView(comptime T: type) type {
    return struct {
        py_list: *PyObject,

        const Self = @This();
        pub const ElementType = T;

        /// Get an element by index, returns null if conversion fails
        pub fn get(self: Self, index: usize) ?T {
            const idx: py.Py_ssize_t = @intCast(index);
            const py_item = py.PyList_GetItem(self.py_list, idx) orelse return null;
            return Conversions.fromPy(T, py_item) catch null;
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
                return Conversions.fromPy(T, py_item) catch null;
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

// ============================================================================
// Set Support - Zero-copy access to Python sets
// ============================================================================

/// Zero-copy view of a Python set for use as a function parameter.
/// Provides iterator access without allocating memory.
/// Usage: fn process_set(items: SetView(i64)) void { ... }
pub fn SetView(comptime T: type) type {
    return struct {
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
            const py_val = Conversions.toPy(T, value) orelse return false;
            defer py.Py_DecRef(py_val);
            return py.PySet_Contains(self.py_set, py_val) == 1;
        }

        /// Iterator over set elements using Python's native iterator protocol.
        /// This is more efficient than the previous implementation which
        /// created a temporary list copy of the entire set.
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
                return Conversions.fromPy(T, py_item) catch null;
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
        items: []const T,

        pub const ElementType = T;
    };
}

/// Marker type for frozen set returns
pub fn FrozenSet(comptime T: type) type {
    return struct {
        items: []const T,

        pub const ElementType = T;
        pub const is_frozen = true;
    };
}

// ============================================================================
// GIL (Global Interpreter Lock) Control
// ============================================================================

/// RAII-style GIL releaser. Releases the GIL on creation, reacquires on deinit.
/// Use this when you have CPU-intensive code that doesn't touch Python objects.
///
/// Example:
/// ```zig
/// fn heavy_computation(n: i64) i64 {
///     // Release the GIL while doing CPU-intensive work
///     const gil = pyoz.releaseGIL();
///     defer gil.acquire();
///
///     // This code runs without the GIL - other Python threads can run
///     var result: i64 = 0;
///     for (0..@intCast(n)) |i| {
///         result += compute(i);
///     }
///     return result;
/// }
/// ```
pub const GILGuard = struct {
    state: ?*py.PyThreadState,

    /// Reacquire the GIL
    pub fn acquire(self: GILGuard) void {
        py.PyEval_RestoreThread(self.state);
    }
};

/// Release the GIL, allowing other Python threads to run.
/// Returns a guard that must be used to reacquire the GIL.
/// IMPORTANT: Do not access any Python objects while the GIL is released!
pub fn releaseGIL() GILGuard {
    return .{ .state = py.PyEval_SaveThread() };
}

/// Low-level GIL state for acquiring GIL from non-Python threads
pub const GILState = struct {
    state: py.PyGILState_STATE,

    /// Release the GIL
    pub fn release(self: GILState) void {
        py.PyGILState_Release(self.state);
    }
};

/// Acquire the GIL from a non-Python thread.
/// Use this when calling into Python from a Zig thread that wasn't created by Python.
pub fn acquireGIL() GILState {
    return .{ .state = py.PyGILState_Ensure() };
}

/// Execute a function while holding the GIL.
/// This is similar to PyO3's `Python::with_gil` pattern.
/// The GIL is automatically released when the function returns.
///
/// Usage from a non-Python thread:
/// ```zig
/// const result = pyoz.withGIL(struct {
///     fn call(python: *pyoz.Python) i64 {
///         python.exec("x = 42") catch return -1;
///         return python.eval(i64, "x") catch -1;
///     }
/// }.call);
/// ```
///
/// Or with a closure-like pattern using a context struct:
/// ```zig
/// const Context = struct {
///     multiplier: i64,
///
///     pub fn call(self: *@This(), python: *pyoz.Python) i64 {
///         const x = python.eval(i64, "21") catch return -1;
///         return x * self.multiplier;
///     }
/// };
/// var ctx = Context{ .multiplier = 2 };
/// const result = pyoz.withGILContext(&ctx, Context.call);
/// ```
pub fn withGIL(comptime callback: fn (*Python) anyerror!void) !void {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;
    // Note: we don't deinit Python here as we're just accessing an already-initialized interpreter

    return callback(&python);
}

/// Execute a function with a return value while holding the GIL.
pub fn withGILReturn(comptime T: type, comptime callback: fn (*Python) anyerror!T) !T {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;

    return callback(&python);
}

/// Execute a function with context while holding the GIL.
/// Useful for passing data into the GIL-protected section.
pub fn withGILContext(
    comptime Ctx: type,
    ctx: *Ctx,
    comptime callback: fn (*Ctx, *Python) anyerror!void,
) !void {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;

    return callback(ctx, &python);
}

/// Execute a function with context and return value while holding the GIL.
pub fn withGILContextReturn(
    comptime Ctx: type,
    comptime T: type,
    ctx: *Ctx,
    comptime callback: fn (*Ctx, *Python) anyerror!T,
) !T {
    const gil = acquireGIL();
    defer gil.release();

    var python = Python.init() catch return error.InitializationFailed;

    return callback(ctx, &python);
}

// ============================================================================
// Type Conversion
// ============================================================================

/// Type conversion implementations - creates a converter aware of registered classes
pub fn Converter(comptime class_types: []const type) type {
    return struct {
        /// Convert Zig value to Python object
        pub fn toPy(comptime T: type, value: T) ?*PyObject {
            const info = @typeInfo(T);

            return switch (info) {
                .int => |int_info| {
                    // Handle 128-bit integers via string conversion
                    if (int_info.bits > 64) {
                        var buf: [48]u8 = undefined;
                        const str = std.fmt.bufPrintZ(&buf, "{d}", .{value}) catch return null;
                        return py.PyLong_FromString(str, null, 10);
                    }
                    if (int_info.signedness == .signed) {
                        return py.PyLong_FromLongLong(@intCast(value));
                    } else {
                        return py.PyLong_FromUnsignedLongLong(@intCast(value));
                    }
                },
                .comptime_int => py.PyLong_FromLongLong(@intCast(value)),
                .float => py.PyFloat_FromDouble(@floatCast(value)),
                .comptime_float => py.PyFloat_FromDouble(@floatCast(value)),
                .bool => py.Py_RETURN_BOOL(value),
                .pointer => |ptr| {
                    // Handle *PyObject directly - just return it as-is
                    if (ptr.child == PyObject) {
                        return value;
                    }
                    // String slice
                    if (ptr.size == .slice and ptr.child == u8) {
                        return py.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
                    }
                    // Null-terminated string (many-pointer)
                    if (ptr.size == .many and ptr.child == u8 and ptr.sentinel_ptr != null) {
                        return py.PyUnicode_FromString(value);
                    }
                    // String literal (*const [N:0]u8) - pointer to null-terminated array
                    if (ptr.size == .one) {
                        const child_info = @typeInfo(ptr.child);
                        if (child_info == .array) {
                            const arr = child_info.array;
                            if (arr.child == u8 and arr.sentinel_ptr != null) {
                                return py.PyUnicode_FromString(value);
                            }
                        }
                    }
                    // Generic slice -> Python list
                    if (ptr.size == .slice) {
                        const list = py.PyList_New(@intCast(value.len)) orelse return null;
                        for (value, 0..) |item, i| {
                            const py_item = toPy(ptr.child, item) orelse {
                                py.Py_DecRef(list);
                                return null;
                            };
                            // PyList_SetItem steals reference
                            if (py.PyList_SetItem(list, @intCast(i), py_item) < 0) {
                                py.Py_DecRef(list);
                                return null;
                            }
                        }
                        return list;
                    }
                    // Check if it's a pointer to a registered class - wrap it
                    inline for (class_types) |ClassType| {
                        if (ptr.child == ClassType) {
                            // TODO: Create a new Python object wrapping this pointer
                            // For now, return null - we'd need to copy the data
                            return null;
                        }
                    }
                    return null;
                },
                .optional => {
                    if (value) |v| {
                        return toPy(@TypeOf(v), v);
                    } else {
                        // If an exception is already set, return null (error indicator)
                        // Otherwise return None
                        if (py.PyErr_Occurred() != null) {
                            return null;
                        }
                        return py.Py_RETURN_NONE();
                    }
                },
                .error_union => {
                    if (value) |v| {
                        return toPy(@TypeOf(v), v);
                    } else |_| {
                        return null;
                    }
                },
                .void => py.Py_RETURN_NONE(),
                .@"struct" => |struct_info| {
                    // Handle Complex type - convert to Python complex
                    if (T == Complex) {
                        return py.PyComplex_FromDoubles(value.real, value.imag);
                    }

                    // Handle DateTime types
                    if (T == DateTime) {
                        return py.PyDateTime_FromDateAndTime(
                            @intCast(value.year),
                            @intCast(value.month),
                            @intCast(value.day),
                            @intCast(value.hour),
                            @intCast(value.minute),
                            @intCast(value.second),
                            @intCast(value.microsecond),
                        );
                    }

                    if (T == Date) {
                        return py.PyDate_FromDate(
                            @intCast(value.year),
                            @intCast(value.month),
                            @intCast(value.day),
                        );
                    }

                    if (T == Time) {
                        return py.PyTime_FromTime(
                            @intCast(value.hour),
                            @intCast(value.minute),
                            @intCast(value.second),
                            @intCast(value.microsecond),
                        );
                    }

                    if (T == TimeDelta) {
                        return py.PyDelta_FromDSU(
                            value.days,
                            value.seconds,
                            value.microseconds,
                        );
                    }

                    // Handle Bytes type
                    if (T == Bytes) {
                        return py.PyBytes_FromStringAndSize(value.data.ptr, @intCast(value.data.len));
                    }

                    // Handle Path type
                    if (T == Path) {
                        return py.PyPath_FromString(value.path);
                    }

                    // Handle Decimal type
                    if (T == Decimal) {
                        return PyDecimal_FromString(value.value);
                    }

                    // Handle tuple returns - convert struct to Python tuple
                    if (struct_info.is_tuple) {
                        const fields = struct_info.fields;
                        const tuple = py.PyTuple_New(@intCast(fields.len)) orelse return null;
                        inline for (fields, 0..) |field, i| {
                            const py_val = toPy(field.type, @field(value, field.name)) orelse {
                                py.Py_DecRef(tuple);
                                return null;
                            };
                            // PyTuple_SetItem steals reference, so don't decref py_val
                            if (py.PyTuple_SetItem(tuple, @intCast(i), py_val) < 0) {
                                py.Py_DecRef(tuple);
                                return null;
                            }
                        }
                        return tuple;
                    }

                    // Check if this is a Dict type - convert entries to Python dict
                    if (@hasDecl(T, "KeyType") and @hasDecl(T, "ValueType") and @hasDecl(T, "Entry")) {
                        const dict = py.PyDict_New() orelse return null;
                        for (value.entries) |entry| {
                            const py_key = toPy(T.KeyType, entry.key) orelse {
                                py.Py_DecRef(dict);
                                return null;
                            };
                            const py_val = toPy(T.ValueType, entry.value) orelse {
                                py.Py_DecRef(py_key);
                                py.Py_DecRef(dict);
                                return null;
                            };
                            if (py.PyDict_SetItem(dict, py_key, py_val) < 0) {
                                py.Py_DecRef(py_key);
                                py.Py_DecRef(py_val);
                                py.Py_DecRef(dict);
                                return null;
                            }
                            py.Py_DecRef(py_key);
                            py.Py_DecRef(py_val);
                        }
                        return dict;
                    }

                    // Check if this is a Set or FrozenSet type - convert items to Python set
                    if (@hasDecl(T, "ElementType") and @hasField(T, "items") and !@hasDecl(T, "KeyType")) {
                        const is_frozen = @hasDecl(T, "is_frozen") and T.is_frozen;
                        const set_obj = if (is_frozen)
                            py.PyFrozenSet_New(null)
                        else
                            py.PySet_New(null);
                        const set = set_obj orelse return null;

                        for (value.items) |item| {
                            const py_item = toPy(T.ElementType, item) orelse {
                                py.Py_DecRef(set);
                                return null;
                            };
                            if (py.PySet_Add(set, py_item) < 0) {
                                py.Py_DecRef(py_item);
                                py.Py_DecRef(set);
                                return null;
                            }
                            py.Py_DecRef(py_item);
                        }
                        return set;
                    }

                    // Check if this is a registered class type - create a new Python object
                    inline for (class_types) |ClassType| {
                        if (T == ClassType) {
                            const Wrapper = class_mod.getWrapper(ClassType);
                            // Allocate a new Python object
                            const py_obj = py.PyObject_New(Wrapper.PyWrapper, &Wrapper.type_object) orelse return null;
                            // Copy the data
                            py_obj.getData().* = value;
                            return @ptrCast(py_obj);
                        }
                    }

                    return null;
                },
                else => null,
            };
        }

        /// Convert Python object to Zig value with class type awareness
        pub fn fromPy(comptime T: type, obj: *PyObject) !T {
            const info = @typeInfo(T);

            // Check if T is a pointer to a registered class type
            if (info == .pointer) {
                const ptr_info = info.pointer;
                const Child = ptr_info.child;

                // Handle *PyObject directly - just return the object as-is
                if (Child == PyObject) {
                    return obj;
                }

                // Check each registered class type
                inline for (class_types) |ClassType| {
                    if (Child == ClassType) {
                        const Wrapper = class_mod.getWrapper(ClassType);
                        if (ptr_info.is_const) {
                            return Wrapper.unwrapConst(obj) orelse return error.TypeError;
                        } else {
                            return Wrapper.unwrap(obj) orelse return error.TypeError;
                        }
                    }
                }

                // Handle string slices
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    if (!py.PyUnicode_Check(obj)) {
                        return error.TypeError;
                    }
                    var size: py.Py_ssize_t = 0;
                    const ptr_data = py.PyUnicode_AsUTF8AndSize(obj, &size) orelse return error.ConversionError;
                    return ptr_data[0..@intCast(size)];
                }

                return error.TypeError;
            }

            // Check if T is Complex type
            if (T == Complex) {
                if (py.PyComplex_Check(obj)) {
                    return Complex{
                        .real = py.PyComplex_RealAsDouble(obj),
                        .imag = py.PyComplex_ImagAsDouble(obj),
                    };
                } else if (py.PyFloat_Check(obj)) {
                    return Complex{
                        .real = py.PyFloat_AsDouble(obj),
                        .imag = 0.0,
                    };
                } else if (py.PyLong_Check(obj)) {
                    return Complex{
                        .real = py.PyLong_AsDouble(obj),
                        .imag = 0.0,
                    };
                }
                return error.TypeError;
            }

            // Check if T is DateTime type
            if (T == DateTime) {
                if (py.PyDateTime_Check(obj)) {
                    return DateTime{
                        .year = @intCast(py.PyDateTime_GET_YEAR(obj)),
                        .month = @intCast(py.PyDateTime_GET_MONTH(obj)),
                        .day = @intCast(py.PyDateTime_GET_DAY(obj)),
                        .hour = @intCast(py.PyDateTime_DATE_GET_HOUR(obj)),
                        .minute = @intCast(py.PyDateTime_DATE_GET_MINUTE(obj)),
                        .second = @intCast(py.PyDateTime_DATE_GET_SECOND(obj)),
                        .microsecond = @intCast(py.PyDateTime_DATE_GET_MICROSECOND(obj)),
                    };
                }
                return error.TypeError;
            }

            // Check if T is Date type
            if (T == Date) {
                if (py.PyDate_Check(obj)) {
                    return Date{
                        .year = @intCast(py.PyDateTime_GET_YEAR(obj)),
                        .month = @intCast(py.PyDateTime_GET_MONTH(obj)),
                        .day = @intCast(py.PyDateTime_GET_DAY(obj)),
                    };
                }
                return error.TypeError;
            }

            // Check if T is Time type
            if (T == Time) {
                if (py.PyTime_Check(obj)) {
                    return Time{
                        .hour = @intCast(py.PyDateTime_TIME_GET_HOUR(obj)),
                        .minute = @intCast(py.PyDateTime_TIME_GET_MINUTE(obj)),
                        .second = @intCast(py.PyDateTime_TIME_GET_SECOND(obj)),
                        .microsecond = @intCast(py.PyDateTime_TIME_GET_MICROSECOND(obj)),
                    };
                }
                return error.TypeError;
            }

            // Check if T is TimeDelta type
            if (T == TimeDelta) {
                if (py.PyDelta_Check(obj)) {
                    return TimeDelta{
                        .days = py.PyDateTime_DELTA_GET_DAYS(obj),
                        .seconds = py.PyDateTime_DELTA_GET_SECONDS(obj),
                        .microseconds = py.PyDateTime_DELTA_GET_MICROSECONDS(obj),
                    };
                }
                return error.TypeError;
            }

            // Check if T is Bytes type
            if (T == Bytes) {
                if (py.PyBytes_Check(obj)) {
                    const size = py.PyBytes_Size(obj);
                    const ptr = py.PyBytes_AsString(obj) orelse return error.ConversionError;
                    return Bytes{ .data = ptr[0..@intCast(size)] };
                } else if (py.PyByteArray_Check(obj)) {
                    const size = py.PyByteArray_Size(obj);
                    const ptr = py.PyByteArray_AsString(obj) orelse return error.ConversionError;
                    return Bytes{ .data = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is ByteArray type
            if (T == ByteArray) {
                if (py.PyByteArray_Check(obj)) {
                    const size = py.PyByteArray_Size(obj);
                    const ptr = py.PyByteArray_AsString(obj) orelse return error.ConversionError;
                    return ByteArray{ .data = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is Decimal type
            if (T == Decimal) {
                if (PyDecimal_Check(obj)) {
                    const str_val = PyDecimal_AsString(obj) orelse return error.ConversionError;
                    return Decimal{ .value = str_val };
                } else if (py.PyLong_Check(obj) or py.PyFloat_Check(obj)) {
                    // Also accept int/float - convert via str()
                    const str_obj = py.PyObject_Str(obj) orelse return error.ConversionError;
                    defer py.Py_DecRef(str_obj);
                    var size: py.Py_ssize_t = 0;
                    const ptr = py.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return error.ConversionError;
                    return Decimal{ .value = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is Path type
            if (T == Path) {
                if (py.PyPath_Check(obj)) {
                    const path_str = py.PyPath_AsString(obj) orelse return error.ConversionError;
                    return Path{ .path = path_str };
                } else if (py.PyUnicode_Check(obj)) {
                    // Also accept plain strings as paths
                    var size: py.Py_ssize_t = 0;
                    const ptr = py.PyUnicode_AsUTF8AndSize(obj, &size) orelse return error.ConversionError;
                    return Path{ .path = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is a DictView type
            if (info == .@"struct" and @hasDecl(T, "py_dict") == false and @hasField(T, "py_dict")) {
                if (!py.PyDict_Check(obj)) {
                    return error.TypeError;
                }
                return T{ .py_dict = obj };
            }

            // Check if T is a ListView type
            if (info == .@"struct" and @hasDecl(T, "py_list") == false and @hasField(T, "py_list")) {
                if (!py.PyList_Check(obj)) {
                    return error.TypeError;
                }
                return T{ .py_list = obj };
            }

            // Check if T is a SetView type
            if (info == .@"struct" and @hasDecl(T, "py_set") == false and @hasField(T, "py_set")) {
                if (!py.PyAnySet_Check(obj)) {
                    return error.TypeError;
                }
                return T{ .py_set = obj };
            }

            return switch (info) {
                .int => |int_info| {
                    if (!py.PyLong_Check(obj)) {
                        return error.TypeError;
                    }
                    // Handle 128-bit integers via string conversion
                    if (int_info.bits > 64) {
                        const str_obj = py.PyObject_Str(obj) orelse return error.ConversionError;
                        defer py.Py_DecRef(str_obj);
                        var size: py.Py_ssize_t = 0;
                        const ptr = py.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return error.ConversionError;
                        const str = ptr[0..@intCast(size)];
                        if (int_info.signedness == .signed) {
                            return std.fmt.parseInt(T, str, 10) catch return error.ConversionError;
                        } else {
                            return std.fmt.parseUnsigned(T, str, 10) catch return error.ConversionError;
                        }
                    }
                    if (int_info.signedness == .signed) {
                        const val = py.PyLong_AsLongLong(obj);
                        if (py.PyErr_Occurred() != null) return error.ConversionError;
                        return @intCast(val);
                    } else {
                        const val = py.PyLong_AsUnsignedLongLong(obj);
                        if (py.PyErr_Occurred() != null) return error.ConversionError;
                        return @intCast(val);
                    }
                },
                .float => {
                    if (py.PyFloat_Check(obj)) {
                        return @floatCast(py.PyFloat_AsDouble(obj));
                    } else if (py.PyLong_Check(obj)) {
                        return @floatCast(py.PyLong_AsDouble(obj));
                    }
                    return error.TypeError;
                },
                .bool => {
                    return py.PyObject_IsTrue(obj) == 1;
                },
                .optional => |opt| {
                    if (py.PyNone_Check(obj)) {
                        return null;
                    }
                    return try fromPy(opt.child, obj);
                },
                .array => |arr| {
                    // Fixed-size array from Python list
                    if (!py.PyList_Check(obj)) {
                        return error.TypeError;
                    }
                    const list_len = py.PyList_Size(obj);
                    if (list_len != arr.len) {
                        return error.WrongArgumentCount;
                    }
                    var result: T = undefined;
                    for (0..arr.len) |i| {
                        const item = py.PyList_GetItem(obj, @intCast(i)) orelse return error.InvalidArgument;
                        result[i] = try fromPy(arr.child, item);
                    }
                    return result;
                },
                else => error.TypeError,
            };
        }
    };
}

/// Basic conversions (no class awareness) - for backwards compatibility
pub const Conversions = Converter(&[_]type{});

// ============================================================================
// Function Wrapper Generator
// ============================================================================

/// Generate a Python-callable wrapper for a Zig function with class type awareness
pub fn wrapFunctionWithClasses(comptime zig_func: anytype, comptime class_types: []const type) py.PyCFunction {
    const Conv = Converter(class_types);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = fn_info.return_type orelse void;

    return struct {
        fn wrapper(self: ?*PyObject, args: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            const zig_args = parseArgs(params, args) catch |err| {
                setError(err);
                return null;
            };

            const result = @call(.auto, zig_func, zig_args);
            return handleReturn(ReturnType, result);
        }

        fn parseArgs(comptime parameters: anytype, args: ?*PyObject) !ArgsTuple(parameters) {
            var result: ArgsTuple(parameters) = undefined;

            if (parameters.len == 0) {
                return result;
            }

            const py_args = args orelse return error.MissingArguments;
            const arg_count = py.PyTuple_Size(py_args);

            if (arg_count != parameters.len) {
                return error.WrongArgumentCount;
            }

            inline for (parameters, 0..) |param, i| {
                const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse return error.InvalidArgument;
                result[i] = try Conv.fromPy(param.type.?, item);
            }

            return result;
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);

            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    setError(err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }

        fn setError(err: anyerror) void {
            const msg = @errorName(err);
            py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
        }
    }.wrapper;
}

/// Generate a Python-callable wrapper for a Zig function (no class awareness)
pub fn wrapFunction(comptime zig_func: anytype) py.PyCFunction {
    return wrapFunctionWithClasses(zig_func, &[_]type{});
}

fn ArgsTuple(comptime params: anytype) type {
    var types: [params.len]type = undefined;
    for (params, 0..) |param, i| {
        types[i] = param.type.?;
    }
    return std.meta.Tuple(&types);
}

/// Type for keyword function signature (C calling convention)
pub const PyCFunctionWithKeywords = *const fn (?*PyObject, ?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;

/// Generate a Python-callable wrapper for a Zig function with named keyword arguments
/// The function should take Args(SomeStruct) as its parameter
pub fn wrapFunctionWithNamedKeywords(comptime zig_func: anytype, comptime class_types: []const type) PyCFunctionWithKeywords {
    const Conv = Converter(class_types);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = fn_info.return_type orelse void;

    // Get the Args wrapper type and the inner struct type
    const ArgsWrapperType = params[0].type.?;
    const ArgsStructType = ArgsWrapperType.ArgsStruct;
    const args_fields = @typeInfo(ArgsStructType).@"struct".fields;

    return struct {
        fn wrapper(self: ?*PyObject, args: ?*PyObject, kwargs: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            var result_args: ArgsStructType = undefined;

            // Get positional args count
            const pos_count: usize = if (args) |a| @intCast(py.PyTuple_Size(a)) else 0;

            // Parse each field
            inline for (args_fields, 0..) |field, i| {
                const has_default = field.default_value_ptr != null;
                const is_optional = @typeInfo(field.type) == .optional;

                // Try positional first
                if (i < pos_count) {
                    const item = py.PyTuple_GetItem(args.?, @intCast(i)) orelse {
                        setError(error.InvalidArgument);
                        return null;
                    };
                    if (is_optional and py.PyNone_Check(item)) {
                        @field(result_args, field.name) = null;
                    } else if (is_optional) {
                        const inner_type = @typeInfo(field.type).optional.child;
                        @field(result_args, field.name) = Conv.fromPy(inner_type, item) catch {
                            setFieldError(field.name);
                            return null;
                        };
                    } else {
                        @field(result_args, field.name) = Conv.fromPy(field.type, item) catch {
                            setFieldError(field.name);
                            return null;
                        };
                    }
                } else if (kwargs) |kw| {
                    // Try keyword argument by name
                    if (py.PyDict_GetItemString(kw, field.name.ptr)) |item| {
                        if (is_optional and py.PyNone_Check(item)) {
                            @field(result_args, field.name) = null;
                        } else if (is_optional) {
                            const inner_type = @typeInfo(field.type).optional.child;
                            @field(result_args, field.name) = Conv.fromPy(inner_type, item) catch {
                                setFieldError(field.name);
                                return null;
                            };
                        } else {
                            @field(result_args, field.name) = Conv.fromPy(field.type, item) catch {
                                setFieldError(field.name);
                                return null;
                            };
                        }
                    } else if (has_default) {
                        // Use default value
                        @field(result_args, field.name) = field.defaultValue().?;
                    } else if (is_optional) {
                        @field(result_args, field.name) = null;
                    } else {
                        setMissingError(field.name);
                        return null;
                    }
                } else if (has_default) {
                    // Use default value
                    @field(result_args, field.name) = field.defaultValue().?;
                } else if (is_optional) {
                    @field(result_args, field.name) = null;
                } else {
                    setMissingError(field.name);
                    return null;
                }
            }

            // Call function with wrapped args
            const wrapped_args = ArgsWrapperType{ .value = result_args };
            const result = zig_func(wrapped_args);

            return handleReturn(ReturnType, result);
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);
            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    setError(err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }

        fn setError(err: anyerror) void {
            const msg = @errorName(err);
            py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
        }

        fn setFieldError(comptime field_name: []const u8) void {
            py.PyErr_SetString(py.PyExc_TypeError(), "Invalid type for argument: " ++ field_name);
        }

        fn setMissingError(comptime field_name: []const u8) void {
            py.PyErr_SetString(py.PyExc_TypeError(), "Missing required argument: " ++ field_name);
        }
    }.wrapper;
}

/// Generate a Python-callable wrapper for a Zig function with keyword argument support
/// Optional parameters (?T) are treated as optional keyword arguments
pub fn wrapFunctionWithKeywords(comptime zig_func: anytype, comptime class_types: []const type) PyCFunctionWithKeywords {
    const Conv = Converter(class_types);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = fn_info.return_type orelse void;

    return struct {
        // Generate parameter names at comptime (arg0, arg1, etc.)
        const num_params = params.len;

        // Pre-generate kwarg names at comptime to avoid runtime formatting
        const kwarg_names = blk: {
            var names: [num_params][*:0]const u8 = undefined;
            for (0..num_params) |i| {
                names[i] = std.fmt.comptimePrint("arg{d}", .{i});
            }
            break :blk names;
        };

        // Count required vs optional parameters
        const num_required = countRequired();
        const num_optional = num_params - num_required;

        fn countRequired() usize {
            var count: usize = 0;
            for (params) |param| {
                const ParamType = param.type.?;
                if (@typeInfo(ParamType) != .optional) {
                    count += 1;
                }
            }
            return count;
        }

        fn wrapper(self: ?*PyObject, args: ?*PyObject, kwargs: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            const zig_args = parseArgsWithKwargs(args, kwargs) catch |err| {
                setError(err);
                return null;
            };

            const result = @call(.auto, zig_func, zig_args);
            return handleReturn(ReturnType, result);
        }

        fn parseArgsWithKwargs(args: ?*PyObject, kwargs: ?*PyObject) !ArgsTuple(params) {
            var result: ArgsTuple(params) = undefined;

            // Get positional args count
            const pos_count: usize = if (args) |a| @intCast(py.PyTuple_Size(a)) else 0;

            // Validate we have at least the required args
            if (pos_count < num_required) {
                // Check if kwargs can fill in the rest
                var kwargs_provided: usize = 0;
                if (kwargs) |kw| {
                    kwargs_provided = @intCast(py.PyDict_Size(kw));
                }
                if (pos_count + kwargs_provided < num_required) {
                    return error.WrongArgumentCount;
                }
            }

            // Parse each parameter
            inline for (params, 0..) |param, i| {
                const ParamType = param.type.?;
                const is_optional = @typeInfo(ParamType) == .optional;

                // Try to get from positional args first
                if (i < pos_count) {
                    const item = py.PyTuple_GetItem(args.?, @intCast(i)) orelse return error.InvalidArgument;
                    if (is_optional) {
                        // Wrap in optional
                        const InnerType = @typeInfo(ParamType).optional.child;
                        if (py.PyNone_Check(item)) {
                            result[i] = null;
                        } else {
                            result[i] = try Conv.fromPy(InnerType, item);
                        }
                    } else {
                        result[i] = try Conv.fromPy(ParamType, item);
                    }
                } else if (kwargs != null) {
                    // Try to get from kwargs using comptime-generated parameter name
                    if (py.PyDict_GetItemString(kwargs.?, kwarg_names[i])) |item| {
                        if (is_optional) {
                            const InnerType = @typeInfo(ParamType).optional.child;
                            if (py.PyNone_Check(item)) {
                                result[i] = null;
                            } else {
                                result[i] = try Conv.fromPy(InnerType, item);
                            }
                        } else {
                            result[i] = try Conv.fromPy(ParamType, item);
                        }
                    } else if (is_optional) {
                        // Optional param not provided - use null
                        result[i] = null;
                    } else {
                        return error.MissingArguments;
                    }
                } else if (is_optional) {
                    // Optional param not provided - use null
                    result[i] = null;
                } else {
                    return error.MissingArguments;
                }
            }

            return result;
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);

            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    setError(err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }

        fn setError(err: anyerror) void {
            const msg = @errorName(err);
            py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
        }
    }.wrapper;
}

// ============================================================================
// Module Definition Helpers
// ============================================================================

/// Function definition entry - stores info needed to wrap at module creation time
pub fn FuncDefEntry(comptime Func: type) type {
    return struct {
        name: [*:0]const u8,
        func: Func,
        doc: ?[*:0]const u8,
    };
}

/// Class definition for the module
pub const ClassDef = struct {
    name: [*:0]const u8,
    type_obj: *PyTypeObject,
    zig_type: type,
};

/// Create a class definition from a Zig struct
pub fn class(comptime name: [*:0]const u8, comptime T: type) ClassDef {
    return .{
        .name = name,
        .type_obj = &class_mod.getWrapper(T).type_object,
        .zig_type = T,
    };
}

// ============================================================================
// Exception Definitions
// ============================================================================

/// Standard Python exception types for use as bases
pub const PyExc = struct {
    pub fn Exception() *PyObject {
        return py.PyExc_Exception();
    }
    pub fn TypeError() *PyObject {
        return py.PyExc_TypeError();
    }
    pub fn ValueError() *PyObject {
        return py.PyExc_ValueError();
    }
    pub fn RuntimeError() *PyObject {
        return py.PyExc_RuntimeError();
    }
    pub fn IndexError() *PyObject {
        return py.PyExc_IndexError();
    }
    pub fn KeyError() *PyObject {
        return py.PyExc_KeyError();
    }
    pub fn AttributeError() *PyObject {
        return py.PyExc_AttributeError();
    }
    pub fn StopIteration() *PyObject {
        return py.PyExc_StopIteration();
    }
};

// ============================================================================
// Base Types for Inheritance
// ============================================================================

/// Get Python base type objects for use with __base__ declaration
/// Usage in struct: pub const __base__ = pyoz.bases.Exception;
pub const bases = struct {
    /// Base: object (default, usually not needed)
    pub fn object() ?*PyTypeObject {
        return @ptrCast(&py.c.PyBaseObject_Type);
    }

    /// Base: Exception
    pub fn Exception() ?*PyTypeObject {
        return @ptrCast(py.c.PyExc_Exception().*.ob_type);
    }

    /// Base: ValueError
    pub fn ValueError() ?*PyTypeObject {
        return @ptrCast(py.c.PyExc_ValueError().*.ob_type);
    }

    /// Base: TypeError
    pub fn TypeError() ?*PyTypeObject {
        return @ptrCast(py.c.PyExc_TypeError().*.ob_type);
    }

    /// Base: RuntimeError
    pub fn RuntimeError() ?*PyTypeObject {
        return @ptrCast(py.c.PyExc_RuntimeError().*.ob_type);
    }

    /// Base: list
    pub fn list() ?*PyTypeObject {
        return @ptrCast(&py.c.PyList_Type);
    }

    /// Base: dict
    pub fn dict() ?*PyTypeObject {
        return @ptrCast(&py.c.PyDict_Type);
    }

    /// Base: set
    pub fn set() ?*PyTypeObject {
        return @ptrCast(&py.c.PySet_Type);
    }

    /// Base: tuple
    pub fn tuple() ?*PyTypeObject {
        return @ptrCast(&py.c.PyTuple_Type);
    }

    /// Base: str
    pub fn str() ?*PyTypeObject {
        return @ptrCast(&py.c.PyUnicode_Type);
    }

    /// Base: int
    pub fn int() ?*PyTypeObject {
        return @ptrCast(&py.c.PyLong_Type);
    }

    /// Base: float
    pub fn float() ?*PyTypeObject {
        return @ptrCast(&py.c.PyFloat_Type);
    }
};

// ============================================================================
// Self Cast Helper - For classes inheriting from Python types
// ============================================================================

/// Cast self pointer to PyObject for use with Python C API functions.
/// Use this in classes that inherit from Python built-in types (list, dict, etc.)
/// where 'self' is actually a pointer to the Python object.
///
/// Example:
/// ```zig
/// const Stack = struct {
///     pub const __base__ = pyoz.bases.list;
///
///     pub fn push(self: *Stack, item: *pyoz.PyObject) void {
///         _ = pyoz.py.PyList_Append(pyoz.object(self), item);
///     }
/// };
/// ```
pub fn object(ptr: anytype) *PyObject {
    const PtrType = @TypeOf(ptr);
    const ptr_info = @typeInfo(PtrType).pointer;
    if (ptr_info.is_const) {
        return @ptrCast(@alignCast(@constCast(ptr)));
    }
    return @ptrCast(@alignCast(ptr));
}

/// Base exception type enum for compile-time specification
pub const ExcBase = enum {
    Exception,
    TypeError,
    ValueError,
    RuntimeError,
    IndexError,
    KeyError,
    AttributeError,
    StopIteration,

    pub fn toPyObject(self: ExcBase) *PyObject {
        return switch (self) {
            .Exception => py.PyExc_Exception(),
            .TypeError => py.PyExc_TypeError(),
            .ValueError => py.PyExc_ValueError(),
            .RuntimeError => py.PyExc_RuntimeError(),
            .IndexError => py.PyExc_IndexError(),
            .KeyError => py.PyExc_KeyError(),
            .AttributeError => py.PyExc_AttributeError(),
            .StopIteration => py.PyExc_StopIteration(),
        };
    }
};

/// Exception definition for the module
pub const ExceptionDef = struct {
    /// Name of the exception (e.g., "MyError")
    name: [*:0]const u8,
    /// Full qualified name (e.g., "mymodule.MyError") - set during module init
    full_name: ?[*:0]const u8 = null,
    /// Base exception type
    base: ExcBase = .Exception,
    /// Documentation string
    doc: ?[*:0]const u8 = null,
    /// Runtime storage for the created exception type
    exception_type: ?*PyObject = null,
};

/// Create an exception definition
pub fn exception(comptime name: [*:0]const u8, comptime opts: struct {
    doc: ?[*:0]const u8 = null,
    base: ExcBase = .Exception,
}) ExceptionDef {
    return .{
        .name = name,
        .doc = opts.doc,
        .base = opts.base,
    };
}

// ============================================================================
// Enum Support - Create Python IntEnums from Zig enums
// ============================================================================

/// Enum definition for the module
pub const EnumDef = struct {
    /// Name of the enum in Python (e.g., "Color")
    name: [*:0]const u8,
    /// The Zig enum type
    zig_type: type,
};

/// Create an enum definition from a Zig enum type (IntEnum)
pub fn enumDef(comptime name: [*:0]const u8, comptime E: type) EnumDef {
    return .{
        .name = name,
        .zig_type = E,
    };
}

/// String enum definition for the module
pub const StrEnumDef = struct {
    /// Name of the enum in Python (e.g., "Status")
    name: [*:0]const u8,
    /// The Zig enum type
    zig_type: type,
};

/// Create a string enum definition from a Zig enum type (StrEnum)
/// The enum field names become the string values
pub fn strEnumDef(comptime name: [*:0]const u8, comptime E: type) StrEnumDef {
    return .{
        .name = name,
        .zig_type = E,
    };
}

/// Helper to raise a custom exception
pub fn raise(exc: *const ExceptionDef, msg: [*:0]const u8) void {
    if (exc.exception_type) |exc_type| {
        py.PyErr_SetString(exc_type, msg);
    } else {
        // Fallback to RuntimeError if exception wasn't initialized
        py.PyErr_SetString(py.PyExc_RuntimeError(), msg);
    }
}

// ============================================================================
// Error Mapping - Map Zig errors to Python exceptions
// ============================================================================

/// Define how a Zig error maps to a Python exception type
pub const ErrorMapping = struct {
    /// The Zig error name (e.g., "OutOfMemory", "InvalidArgument")
    error_name: []const u8,
    /// The Python exception type to use
    exc_type: ExcBase,
    /// Custom message (if null, uses the error name)
    message: ?[*:0]const u8 = null,
};

/// Create an error mapping entry
pub fn mapError(comptime error_name: []const u8, comptime exc_type: ExcBase) ErrorMapping {
    return .{
        .error_name = error_name,
        .exc_type = exc_type,
        .message = null,
    };
}

/// Create an error mapping with custom message
pub fn mapErrorMsg(comptime error_name: []const u8, comptime exc_type: ExcBase, comptime message: [*:0]const u8) ErrorMapping {
    return .{
        .error_name = error_name,
        .exc_type = exc_type,
        .message = message,
    };
}

/// Helper to set a Python exception from a Zig error using the mapping
pub fn setErrorFromMapping(comptime mappings: []const ErrorMapping, err: anyerror) void {
    const err_name = @errorName(err);

    // Search for a mapping
    inline for (mappings) |mapping| {
        if (std.mem.eql(u8, err_name, mapping.error_name)) {
            const exc = mapping.exc_type.toPyObject();
            if (mapping.message) |msg| {
                py.PyErr_SetString(exc, msg);
            } else {
                py.PyErr_SetString(exc, err_name.ptr);
            }
            return;
        }
    }

    // Default: RuntimeError with error name
    py.PyErr_SetString(py.PyExc_RuntimeError(), err_name.ptr);
}

/// Helper to create a function entry
pub fn func(comptime name: [*:0]const u8, comptime function: anytype, comptime doc: ?[*:0]const u8) FuncDefEntry(@TypeOf(function)) {
    return .{
        .name = name,
        .func = function,
        .doc = doc,
    };
}

// ============================================================================
// Keyword Arguments Support
// ============================================================================

/// Function definition with keyword argument support
pub fn KwFuncDefEntry(comptime Func: type) type {
    return struct {
        name: [*:0]const u8,
        func: Func,
        doc: ?[*:0]const u8,
        is_kwargs: bool = true,
    };
}

/// Create a function entry that accepts keyword arguments
/// Functions with optional parameters (?T) will have those as optional kwargs with default null
pub fn kwfunc(comptime name: [*:0]const u8, comptime function: anytype, comptime doc: ?[*:0]const u8) KwFuncDefEntry(@TypeOf(function)) {
    return .{
        .name = name,
        .func = function,
        .doc = doc,
        .is_kwargs = true,
    };
}

// ============================================================================
// Named Keyword Arguments Support
// ============================================================================

/// Define named keyword arguments using a struct.
/// Each field becomes a keyword argument with its name.
/// Optional fields (?T) have a default of null.
/// Fields with default values use those defaults.
///
/// Example:
/// ```zig
/// const GreetArgs = struct {
///     name: []const u8,              // Required
///     greeting: ?[]const u8 = null,  // Optional, default null
///     times: i64 = 1,                // Optional, default 1
/// };
///
/// fn greet(args: pyoz.Args(GreetArgs)) []const u8 {
///     const greeting = args.greeting orelse "Hello";
///     // ...
/// }
/// ```
pub fn Args(comptime T: type) type {
    return struct {
        pub const ArgsStruct = T;
        pub const is_pyoz_args = true;
        value: T,

        // Allow direct field access via the wrapper
        pub fn get(self: @This()) T {
            return self.value;
        }
    };
}

/// Wrapper type for functions with named keyword arguments
pub fn NamedKwFuncDefEntry(comptime Func: type) type {
    return struct {
        name: [*:0]const u8,
        func: Func,
        doc: ?[*:0]const u8,
        is_named_kwargs: bool = true,
    };
}

/// Create a function entry with named keyword arguments
/// The function should accept Args(YourArgsStruct) as its parameter
pub fn kwfunc_named(comptime name: [*:0]const u8, comptime function: anytype, comptime doc: ?[*:0]const u8) NamedKwFuncDefEntry(@TypeOf(function)) {
    return .{
        .name = name,
        .func = function,
        .doc = doc,
        .is_named_kwargs = true,
    };
}

/// Module configuration
pub fn ModuleConfig(comptime FuncTuple: type, comptime num_classes: usize, comptime num_exceptions: usize) type {
    return struct {
        name: [*:0]const u8,
        doc: ?[*:0]const u8 = null,
        funcs: FuncTuple,
        classes: [num_classes]ClassDef,
        exceptions: [num_exceptions]ExceptionDef,
    };
}

/// Extract Zig types from class definitions
fn extractClassTypes(comptime classes: anytype) []const type {
    comptime {
        var types: [classes.len]type = undefined;
        for (classes, 0..) |cls, i| {
            types[i] = cls.zig_type;
        }
        const final = types;
        return &final;
    }
}

/// Generate a wrapper with custom error mapping
pub fn wrapFunctionWithErrorMapping(comptime zig_func: anytype, comptime class_types: []const type, comptime error_mappings: []const ErrorMapping) py.PyCFunction {
    const Conv = Converter(class_types);
    const Fn = @TypeOf(zig_func);
    const fn_info = @typeInfo(Fn).@"fn";
    const params = fn_info.params;
    const ReturnType = fn_info.return_type orelse void;

    return struct {
        fn wrapper(self: ?*PyObject, args: ?*PyObject) callconv(.c) ?*PyObject {
            _ = self;

            const zig_args = parseArgs(params, args) catch |err| {
                setMappedError(err);
                return null;
            };

            const result = @call(.auto, zig_func, zig_args);
            return handleReturn(ReturnType, result);
        }

        fn parseArgs(comptime parameters: anytype, args: ?*PyObject) !ArgsTuple(parameters) {
            var result: ArgsTuple(parameters) = undefined;

            if (parameters.len == 0) {
                return result;
            }

            const py_args = args orelse return error.MissingArguments;
            const arg_count = py.PyTuple_Size(py_args);

            if (arg_count != parameters.len) {
                return error.WrongArgumentCount;
            }

            inline for (parameters, 0..) |param, i| {
                const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse return error.InvalidArgument;
                result[i] = try Conv.fromPy(param.type.?, item);
            }

            return result;
        }

        fn handleReturn(comptime RT: type, result: anytype) ?*PyObject {
            const rt_info = @typeInfo(RT);

            if (rt_info == .error_union) {
                if (result) |value| {
                    return Conv.toPy(@TypeOf(value), value);
                } else |err| {
                    setMappedError(err);
                    return null;
                }
            } else {
                return Conv.toPy(RT, result);
            }
        }

        fn setMappedError(err: anyerror) void {
            setErrorFromMapping(error_mappings, err);
        }
    }.wrapper;
}

// Helper to check if a type or any of its components uses Decimal
fn usesDecimalType(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => T == Decimal,
        .optional => |opt| usesDecimalType(opt.child),
        .pointer => |ptr| usesDecimalType(ptr.child),
        else => false,
    };
}

// Helper to check if a type or any of its components uses DateTime types
fn usesDateTimeType(comptime T: type) bool {
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => T == DateTime or T == Date or T == Time or T == TimeDelta,
        .optional => |opt| usesDateTimeType(opt.child),
        .pointer => |ptr| usesDateTimeType(ptr.child),
        else => false,
    };
}

// Check if any function in the list uses Decimal types
fn anyFuncUsesDecimal(comptime funcs_list: anytype) bool {
    for (funcs_list) |f| {
        const Fn = @TypeOf(f.func);
        const fn_info = @typeInfo(Fn).@"fn";
        // Check return type
        if (fn_info.return_type) |ret| {
            if (usesDecimalType(ret)) return true;
        }
        // Check parameters
        for (fn_info.params) |param| {
            if (param.type) |ptype| {
                if (usesDecimalType(ptype)) return true;
            }
        }
    }
    return false;
}

// Check if any function in the list uses DateTime types
fn anyFuncUsesDateTime(comptime funcs_list: anytype) bool {
    for (funcs_list) |f| {
        const Fn = @TypeOf(f.func);
        const fn_info = @typeInfo(Fn).@"fn";
        // Check return type
        if (fn_info.return_type) |ret| {
            if (usesDateTimeType(ret)) return true;
        }
        // Check parameters
        for (fn_info.params) |param| {
            if (param.type) |ptype| {
                if (usesDateTimeType(ptype)) return true;
            }
        }
    }
    return false;
}

/// Create a Python module from configuration
pub fn module(comptime config: anytype) type {
    const classes = config.classes;
    const funcs = config.funcs;
    const class_types = extractClassTypes(classes);
    const exceptions = if (@hasField(@TypeOf(config), "exceptions")) config.exceptions else &[_]ExceptionDef{};
    const num_exceptions = exceptions.len;
    const error_mappings = if (@hasField(@TypeOf(config), "error_mappings")) config.error_mappings else &[_]ErrorMapping{};
    const enums = if (@hasField(@TypeOf(config), "enums")) config.enums else &[_]EnumDef{};
    const num_enums = enums.len;
    const str_enums = if (@hasField(@TypeOf(config), "str_enums")) config.str_enums else &[_]StrEnumDef{};
    const num_str_enums = str_enums.len;

    // Detect at comptime if this module uses Decimal or DateTime types
    const needs_decimal_init = anyFuncUsesDecimal(funcs);
    const needs_datetime_init = anyFuncUsesDateTime(funcs);

    return struct {
        // Generate method definitions array with class-aware wrappers
        var methods: [funcs.len + 1]PyMethodDef = blk: {
            var m: [funcs.len + 1]PyMethodDef = undefined;
            for (funcs, 0..) |f, i| {
                // Check if this is a named keyword-argument function
                const is_named_kwargs = @hasField(@TypeOf(f), "is_named_kwargs") and f.is_named_kwargs;
                // Check if this is a positional keyword-argument function
                const is_kwargs = @hasField(@TypeOf(f), "is_kwargs") and f.is_kwargs;

                if (is_named_kwargs) {
                    m[i] = .{
                        .ml_name = f.name,
                        .ml_meth = @ptrCast(wrapFunctionWithNamedKeywords(f.func, class_types)),
                        .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                        .ml_doc = f.doc,
                    };
                } else if (is_kwargs) {
                    m[i] = .{
                        .ml_name = f.name,
                        .ml_meth = @ptrCast(wrapFunctionWithKeywords(f.func, class_types)),
                        .ml_flags = py.METH_VARARGS | py.METH_KEYWORDS,
                        .ml_doc = f.doc,
                    };
                } else {
                    // Use error mapping wrapper if mappings are defined
                    if (error_mappings.len > 0) {
                        m[i] = .{
                            .ml_name = f.name,
                            .ml_meth = wrapFunctionWithErrorMapping(f.func, class_types, error_mappings),
                            .ml_flags = py.METH_VARARGS,
                            .ml_doc = f.doc,
                        };
                    } else {
                        m[i] = .{
                            .ml_name = f.name,
                            .ml_meth = wrapFunctionWithClasses(f.func, class_types),
                            .ml_flags = py.METH_VARARGS,
                            .ml_doc = f.doc,
                        };
                    }
                }
            }
            m[funcs.len] = .{
                .ml_name = null,
                .ml_meth = null,
                .ml_flags = 0,
                .ml_doc = null,
            };
            break :blk m;
        };

        var module_def: PyModuleDef = .{
            .m_base = py.PyModuleDef_HEAD_INIT,
            .m_name = config.name,
            .m_doc = config.doc,
            .m_size = -1,
            .m_methods = &methods,
            .m_slots = null,
            .m_traverse = null,
            .m_clear = null,
            .m_free = null,
        };

        // Generate full exception names at comptime (e.g., "mymodule.MyError")
        const exception_full_names: [num_exceptions][256:0]u8 = blk: {
            var names: [num_exceptions][256:0]u8 = undefined;
            for (exceptions, 0..) |exc, i| {
                var buf: [256:0]u8 = [_:0]u8{0} ** 256;
                // Get module name length by finding null terminator
                var mod_len: usize = 0;
                while (config.name[mod_len] != 0) : (mod_len += 1) {}
                // Get exception name length
                var exc_len: usize = 0;
                while (exc.name[exc_len] != 0) : (exc_len += 1) {}
                // Copy module name
                for (0..mod_len) |j| {
                    buf[j] = config.name[j];
                }
                buf[mod_len] = '.';
                // Copy exception name
                for (0..exc_len) |j| {
                    buf[mod_len + 1 + j] = exc.name[j];
                }
                names[i] = buf;
            }
            break :blk names;
        };

        // Runtime storage for exception types
        var exception_types: [num_exceptions]?*PyObject = [_]?*PyObject{null} ** num_exceptions;

        pub fn init() ?*PyObject {
            const mod = py.PyModule_Create(&module_def) orelse return null;

            // Initialize special type APIs at module load time (detected at comptime)
            // This avoids repeated null checks during function calls
            if (needs_datetime_init) {
                _ = initDatetime();
            }
            if (needs_decimal_init) {
                _ = initDecimal();
            }

            // Add classes to the module
            inline for (classes) |cls| {
                // Ready the type first
                if (py.PyType_Ready(cls.type_obj) < 0) {
                    py.Py_DecRef(mod);
                    return null;
                }

                // Add __slots__ tuple with field names to the type's __dict__
                const slots_tuple = class_mod.createSlotsTuple(cls.zig_type);
                if (slots_tuple) |st| {
                    const type_dict = cls.type_obj.tp_dict;
                    if (type_dict) |dict| {
                        _ = py.PyDict_SetItemString(dict, "__slots__", st);
                    }
                    py.Py_DecRef(st);
                }

                // Add class attributes (classattr_NAME declarations)
                if (cls.type_obj.tp_dict) |type_dict| {
                    if (!class_mod.addClassAttributes(cls.zig_type, type_dict)) {
                        py.Py_DecRef(mod);
                        return null;
                    }
                }

                if (py.PyModule_AddType(mod, cls.type_obj) < 0) {
                    py.Py_DecRef(mod);
                    return null;
                }
            }

            // Create and add exceptions to the module
            inline for (0..num_exceptions) |i| {
                const base_exc = exceptions[i].base.toPyObject();
                const exc_type = py.PyErr_NewException(
                    &exception_full_names[i],
                    base_exc,
                    null,
                ) orelse {
                    py.Py_DecRef(mod);
                    return null;
                };
                exception_types[i] = exc_type;

                // Add to module
                if (py.PyModule_AddObject(mod, exceptions[i].name, exc_type) < 0) {
                    py.Py_DecRef(exc_type);
                    py.Py_DecRef(mod);
                    return null;
                }
            }

            // Create and add enums to the module
            inline for (0..num_enums) |i| {
                const enum_def = enums[i];
                const enum_type = module_mod.createEnum(enum_def.zig_type, enum_def.name) orelse {
                    py.Py_DecRef(mod);
                    return null;
                };

                // Add to module (steals reference on success)
                if (py.PyModule_AddObject(mod, enum_def.name, enum_type) < 0) {
                    py.Py_DecRef(enum_type);
                    py.Py_DecRef(mod);
                    return null;
                }
            }

            // Create and add string enums to the module
            inline for (0..num_str_enums) |i| {
                const str_enum_def = str_enums[i];
                const str_enum_type = module_mod.createStrEnum(str_enum_def.zig_type, str_enum_def.name) orelse {
                    py.Py_DecRef(mod);
                    return null;
                };

                // Add to module (steals reference on success)
                if (py.PyModule_AddObject(mod, str_enum_def.name, str_enum_type) < 0) {
                    py.Py_DecRef(str_enum_type);
                    py.Py_DecRef(mod);
                    return null;
                }
            }

            return mod;
        }

        /// Reference to a module exception for raising
        pub const ExceptionRef = struct {
            idx: usize,

            /// Raise this exception with a message
            pub fn raise(self: ExceptionRef, msg: [*:0]const u8) void {
                if (exception_types[self.idx]) |exc_type| {
                    py.PyErr_SetString(exc_type, msg);
                } else {
                    py.PyErr_SetString(py.PyExc_RuntimeError(), msg);
                }
            }
        };

        /// Get an exception reference by index (for use in raise)
        pub fn getException(comptime idx: usize) ExceptionRef {
            return ExceptionRef{ .idx = idx };
        }

        // Expose class types for external use
        pub const registered_classes = class_types;
    };
}

// ============================================================================
// Error types
// ============================================================================

pub const PyErr = error{
    TypeError,
    ValueError,
    RuntimeError,
    ConversionError,
    MissingArguments,
    WrongArgumentCount,
    InvalidArgument,
};

// ============================================================================
// Submodule Helpers - For creating module method arrays manually
// ============================================================================

/// Re-export Module from module.zig
pub const Module = @import("module.zig").Module;

/// Create a method definition entry (for use in manual method arrays)
pub fn methodDef(comptime name: [*:0]const u8, comptime func_ptr: *const py.PyCFunction, comptime doc: ?[*:0]const u8) PyMethodDef {
    return .{
        .ml_name = name,
        .ml_meth = func_ptr.*,
        .ml_flags = py.METH_VARARGS,
        .ml_doc = doc,
    };
}

/// Create a sentinel (null terminator) for method arrays
pub fn methodDefSentinel() PyMethodDef {
    return .{
        .ml_name = null,
        .ml_meth = null,
        .ml_flags = 0,
        .ml_doc = null,
    };
}

/// Wrap a Zig function for use in submodule method arrays
/// Returns a pointer to the wrapper function for use with methodDef
pub fn wrapFunc(comptime zig_func: anytype) py.PyCFunction {
    return wrapFunctionWithErrorMapping(zig_func, &[_]type{}, &[_]ErrorMapping{
        mapError("NegativeValue", .ValueError),
        mapErrorMsg("ValueTooLarge", .ValueError, "Value exceeds maximum"),
        mapError("IndexOutOfBounds", .IndexError),
        mapError("DivisionByZero", .RuntimeError),
    });
}

// ============================================================================
// Python Embedding - Run Python from Zig
// ============================================================================

/// Errors that can occur during Python embedding operations
pub const EmbedError = error{
    /// Python interpreter failed to initialize
    InitializationFailed,
    /// Python code execution failed (exception occurred)
    ExecutionFailed,
    /// Failed to convert a value between Zig and Python
    ConversionFailed,
    /// Failed to import a module
    ImportFailed,
    /// Failed to get an attribute
    AttributeError,
    /// Failed to call a function
    CallFailed,
};

/// High-level Python embedding interface.
/// Provides a convenient way to run Python code from Zig.
///
/// Example usage:
/// ```zig
/// var python = try pyoz.Python.init();
/// defer python.deinit();
///
/// // Execute statements
/// try python.exec("x = 42");
///
/// // Evaluate expressions
/// const result = try python.eval(i64, "x * 2");
/// std.debug.print("Result: {}\n", .{result});
///
/// // Set and get globals
/// try python.setGlobal("name", "World");
/// const greeting = try python.eval([]const u8, "f'Hello, {name}!'");
/// ```
pub const Python = struct {
    /// The __main__ module dictionary (borrowed reference)
    main_dict: *PyObject,

    /// Initialize the Python interpreter.
    /// Must be called before any other Python operations.
    /// Call deinit() when done to clean up.
    pub fn init() EmbedError!Python {
        if (!py.Py_IsInitialized()) {
            py.Py_Initialize();
            if (!py.Py_IsInitialized()) {
                return EmbedError.InitializationFailed;
            }
        }

        const main_module = py.PyImport_AddModule("__main__") orelse
            return EmbedError.InitializationFailed;
        const main_dict = py.PyModule_GetDict(main_module) orelse
            return EmbedError.InitializationFailed;

        return .{ .main_dict = main_dict };
    }

    /// Finalize the Python interpreter.
    /// After calling this, Python cannot be reinitialized in the same process.
    pub fn deinit(self: *Python) void {
        _ = self;
        if (py.Py_IsInitialized()) {
            _ = py.Py_FinalizeEx();
        }
    }

    /// Execute Python statements (no return value).
    /// Use this for statements like assignments, imports, function definitions.
    ///
    /// Example:
    /// ```zig
    /// try python.exec("import math");
    /// try python.exec("def greet(name): return f'Hello, {name}!'");
    /// ```
    pub fn exec(self: *Python, code: [*:0]const u8) EmbedError!void {
        const result = py.PyRun_String(code, py.Py_file_input, self.main_dict, self.main_dict);
        if (result) |r| {
            py.Py_DecRef(r);
        } else {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ExecutionFailed;
        }
    }

    /// Evaluate a Python expression and return the result converted to type T.
    /// Use this for expressions that produce a value.
    ///
    /// Example:
    /// ```zig
    /// const sum = try python.eval(i64, "1 + 2 + 3");
    /// const pi = try python.eval(f64, "math.pi");
    /// const msg = try python.eval([]const u8, "'hello'.upper()");
    /// ```
    pub fn eval(self: *Python, comptime T: type, expr: [*:0]const u8) EmbedError!T {
        const result = py.PyRun_String(expr, py.Py_eval_input, self.main_dict, self.main_dict);
        if (result) |py_result| {
            defer py.Py_DecRef(py_result);
            return Conversions.fromPy(T, py_result) catch return EmbedError.ConversionFailed;
        } else {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ExecutionFailed;
        }
    }

    /// Evaluate a Python expression and return the raw PyObject.
    /// Caller is responsible for calling Py_DecRef on the result.
    ///
    /// Example:
    /// ```zig
    /// const obj = try python.evalObject("[1, 2, 3]");
    /// defer pyoz.py.Py_DecRef(obj);
    /// ```
    pub fn evalObject(self: *Python, expr: [*:0]const u8) EmbedError!*PyObject {
        const result = py.PyRun_String(expr, py.Py_eval_input, self.main_dict, self.main_dict);
        if (result) |py_result| {
            return py_result;
        } else {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ExecutionFailed;
        }
    }

    /// Set a global variable in the Python __main__ namespace.
    ///
    /// Example:
    /// ```zig
    /// try python.setGlobal("count", @as(i64, 42));
    /// try python.setGlobal("name", "Alice");
    /// try python.setGlobal("values", &[_]i64{1, 2, 3});
    /// ```
    pub fn setGlobal(self: *Python, name: [*:0]const u8, value: anytype) EmbedError!void {
        const py_value = Conversions.toPy(@TypeOf(value), value) orelse
            return EmbedError.ConversionFailed;
        defer py.Py_DecRef(py_value);

        if (py.PyDict_SetItemString(self.main_dict, name, py_value) < 0) {
            return EmbedError.ExecutionFailed;
        }
    }

    /// Set a global variable from a raw PyObject.
    /// Does not take ownership of the object (increments refcount).
    pub fn setGlobalObject(self: *Python, name: [*:0]const u8, obj: *PyObject) EmbedError!void {
        if (py.PyDict_SetItemString(self.main_dict, name, obj) < 0) {
            return EmbedError.ExecutionFailed;
        }
    }

    /// Get a global variable from the Python __main__ namespace.
    ///
    /// Example:
    /// ```zig
    /// try python.exec("result = 100");
    /// const result = try python.getGlobal(i64, "result");
    /// ```
    pub fn getGlobal(self: *Python, comptime T: type, name: [*:0]const u8) EmbedError!T {
        const py_value = py.PyDict_GetItemString(self.main_dict, name) orelse
            return EmbedError.AttributeError;
        // PyDict_GetItemString returns borrowed reference, no decref needed
        return Conversions.fromPy(T, py_value) catch return EmbedError.ConversionFailed;
    }

    /// Get a global variable as a raw PyObject (borrowed reference).
    /// Do NOT call Py_DecRef on the result.
    pub fn getGlobalObject(self: *Python, name: [*:0]const u8) ?*PyObject {
        return py.PyDict_GetItemString(self.main_dict, name);
    }

    /// Import a Python module and return it.
    /// Caller is responsible for calling Py_DecRef on the result.
    ///
    /// Example:
    /// ```zig
    /// const math = try python.import("math");
    /// defer pyoz.py.Py_DecRef(math);
    /// ```
    pub fn import(self: *Python, module_name: [*:0]const u8) EmbedError!*PyObject {
        _ = self;
        const mod = py.PyImport_ImportModule(module_name) orelse {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.ImportFailed;
        };
        return mod;
    }

    /// Import a module and make it available as a global variable.
    ///
    /// Example:
    /// ```zig
    /// try python.importAs("math", "m");
    /// const pi = try python.eval(f64, "m.pi");
    /// ```
    pub fn importAs(self: *Python, module_name: [*:0]const u8, as_name: [*:0]const u8) EmbedError!void {
        const mod = try self.import(module_name);
        defer py.Py_DecRef(mod);
        try self.setGlobalObject(as_name, mod);
    }

    /// Call a Python callable with arguments and return the result.
    ///
    /// Example:
    /// ```zig
    /// try python.exec("def add(a, b): return a + b");
    /// const result = try python.call(i64, "add", .{@as(i64, 1), @as(i64, 2)});
    /// ```
    pub fn call(self: *Python, comptime ReturnType: type, func_name: [*:0]const u8, args: anytype) EmbedError!ReturnType {
        const callable = py.PyDict_GetItemString(self.main_dict, func_name) orelse
            return EmbedError.AttributeError;

        const args_info = @typeInfo(@TypeOf(args));
        if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
            @compileError("call() args must be a tuple");
        }

        const fields = args_info.@"struct".fields;
        const py_args = py.PyTuple_New(@intCast(fields.len)) orelse
            return EmbedError.ExecutionFailed;
        defer py.Py_DecRef(py_args);

        inline for (fields, 0..) |field, i| {
            const value = @field(args, field.name);
            const py_value = Conversions.toPy(@TypeOf(value), value) orelse {
                return EmbedError.ConversionFailed;
            };
            // PyTuple_SetItem steals reference
            if (py.PyTuple_SetItem(py_args, @intCast(i), py_value) < 0) {
                return EmbedError.ExecutionFailed;
            }
        }

        const result = py.PyObject_CallFunction(callable, py_args) orelse {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.CallFailed;
        };
        defer py.Py_DecRef(result);

        if (ReturnType == void) {
            return;
        }

        return Conversions.fromPy(ReturnType, result) catch return EmbedError.ConversionFailed;
    }

    /// Call a method on a Python object.
    ///
    /// Example:
    /// ```zig
    /// try python.exec("class Counter:\n    def __init__(self): self.n = 0\n    def inc(self): self.n += 1; return self.n");
    /// try python.exec("c = Counter()");
    /// const obj = python.getGlobalObject("c").?;
    /// const n = try python.callMethod(i64, obj, "inc", .{});
    /// ```
    pub fn callMethod(self: *Python, comptime ReturnType: type, obj: *PyObject, method_name: [*:0]const u8, args: anytype) EmbedError!ReturnType {
        _ = self;

        const method_name_obj = py.PyUnicode_FromString(method_name) orelse
            return EmbedError.ExecutionFailed;
        defer py.Py_DecRef(method_name_obj);

        const method = py.PyObject_GetAttr(obj, method_name_obj) orelse
            return EmbedError.AttributeError;
        defer py.Py_DecRef(method);

        const args_info = @typeInfo(@TypeOf(args));
        if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
            @compileError("callMethod() args must be a tuple");
        }

        const fields = args_info.@"struct".fields;
        const py_args = py.PyTuple_New(@intCast(fields.len)) orelse
            return EmbedError.ExecutionFailed;
        defer py.Py_DecRef(py_args);

        inline for (fields, 0..) |field, i| {
            const value = @field(args, field.name);
            const py_value = Conversions.toPy(@TypeOf(value), value) orelse {
                return EmbedError.ConversionFailed;
            };
            if (py.PyTuple_SetItem(py_args, @intCast(i), py_value) < 0) {
                return EmbedError.ExecutionFailed;
            }
        }

        const result = py.PyObject_CallFunction(method, py_args) orelse {
            if (py.PyErr_Occurred() != null) {
                py.PyErr_Print();
            }
            return EmbedError.CallFailed;
        };
        defer py.Py_DecRef(result);

        if (ReturnType == void) {
            return;
        }

        return Conversions.fromPy(ReturnType, result) catch return EmbedError.ConversionFailed;
    }

    /// Check if a Python exception is currently set.
    pub fn hasError(self: *Python) bool {
        _ = self;
        return py.PyErr_Occurred() != null;
    }

    /// Clear any pending Python exception.
    pub fn clearError(self: *Python) void {
        _ = self;
        py.PyErr_Clear();
    }

    /// Print the current exception to stderr and clear it.
    pub fn printError(self: *Python) void {
        _ = self;
        py.PyErr_Print();
    }

    /// Run a Python script file.
    /// The file path should be a null-terminated string.
    pub fn runFile(self: *Python, filepath: [*:0]const u8) EmbedError!void {
        // Read file using Python's open/read
        var buf: [4096]u8 = undefined;
        const code = std.fmt.bufPrintZ(&buf, "exec(open('{s}').read())", .{filepath}) catch
            return EmbedError.ExecutionFailed;
        try self.exec(code);
    }

    /// Check if the Python interpreter is initialized.
    pub fn isInitialized(self: *Python) bool {
        _ = self;
        return py.Py_IsInitialized();
    }
};
