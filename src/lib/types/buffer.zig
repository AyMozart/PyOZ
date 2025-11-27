//! Buffer types for Python interop
//!
//! Provides BufferView and BufferViewMut for zero-copy access to numpy arrays
//! and other objects supporting the Python buffer protocol.

const std = @import("std");
const py = @import("../python.zig");
const PyObject = py.PyObject;
const Py_ssize_t = py.Py_ssize_t;

// Import complex types for format checking
const complex_types = @import("complex.zig");
const Complex = complex_types.Complex;
const Complex32 = complex_types.Complex32;

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

/// Zero-copy view into a Python buffer (numpy array, bytes, memoryview, etc.)
/// Use this as a function parameter type to receive numpy arrays without copying.
///
/// The view is valid only during the function call - do not store references to the data.
/// For mutable access, use BufferViewMut(T).
///
/// Supported element types: i8, i16, i32, i64, u8, u16, u32, u64, f32, f64, Complex, Complex32
///
/// Example:
/// ```zig
/// fn sum_array(arr: pyoz.BufferView(f64)) f64 {
///     var total: f64 = 0;
///     for (arr.data) |v| total += v;
///     return total;
/// }
/// ```
///
/// Python usage:
/// ```python
/// import numpy as np
/// arr = np.array([1.0, 2.0, 3.0], dtype=np.float64)
/// result = mymodule.sum_array(arr)  # Zero-copy!
/// ```
pub fn BufferView(comptime T: type) type {
    return struct {
        const _is_pyoz_buffer = true;

        /// The underlying data as a Zig slice (read-only)
        data: []const T,
        /// Number of dimensions (1 for 1D array, 2 for 2D, etc.)
        ndim: usize,
        /// Shape of each dimension
        shape: []const Py_ssize_t,
        /// Strides for each dimension (in bytes)
        strides: ?[]const Py_ssize_t,
        /// The Python object (for reference counting)
        _py_obj: *PyObject,
        /// The buffer view (must be released)
        _buffer: py.Py_buffer,

        const Self = @This();
        pub const ElementType = T;
        pub const is_buffer_view = true;
        pub const is_mutable = false;

        /// Get the total number of elements
        pub fn len(self: Self) usize {
            return self.data.len;
        }

        /// Check if the buffer is empty
        pub fn isEmpty(self: Self) bool {
            return self.data.len == 0;
        }

        /// Check if the buffer is C-contiguous (row-major)
        pub fn isContiguous(self: Self) bool {
            return self._buffer.strides == null or self.ndim == 1;
        }

        /// Get element at a flat index
        pub fn get(self: Self, index: usize) T {
            return self.data[index];
        }

        /// Get element at 2D index (row, col) - only valid for 2D arrays
        pub fn get2D(self: Self, row: usize, col: usize) T {
            if (self.ndim != 2) @panic("get2D requires 2D array");
            if (self.strides) |strd| {
                // Use strides for non-contiguous access
                const byte_offset = @as(usize, @intCast(strd[0])) * row + @as(usize, @intCast(strd[1])) * col;
                const ptr: [*]const T = @ptrCast(@alignCast(self._buffer.buf.?));
                const byte_ptr: [*]const u8 = @ptrCast(ptr);
                return @as(*const T, @ptrCast(@alignCast(byte_ptr + byte_offset))).*;
            } else {
                // C-contiguous
                const num_cols: usize = @intCast(self.shape[1]);
                return self.data[row * num_cols + col];
            }
        }

        /// Get the shape as a slice of usizes (convenience method)
        pub fn getShape(self: Self) []const Py_ssize_t {
            return self.shape;
        }

        /// Get number of rows (for 2D arrays)
        pub fn rows(self: Self) usize {
            if (self.ndim < 1) return 0;
            return @intCast(self.shape[0]);
        }

        /// Get number of columns (for 2D arrays)
        pub fn cols(self: Self) usize {
            if (self.ndim < 2) return self.len();
            return @intCast(self.shape[1]);
        }

        /// Iterate over elements (flat iteration)
        pub fn iterator(self: Self) Iterator {
            return .{ .data = self.data, .index = 0 };
        }

        pub const Iterator = struct {
            data: []const T,
            index: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.index >= self.data.len) return null;
                const val = self.data[self.index];
                self.index += 1;
                return val;
            }

            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        /// Release the buffer - called automatically by the wrapper
        pub fn release(self: *Self) void {
            py.PyBuffer_Release(&self._buffer);
        }
    };
}

/// Mutable zero-copy view into a Python buffer (numpy array, bytearray, etc.)
/// Use this when you need to modify the array data in-place.
///
/// Example:
/// ```zig
/// fn scale_array(arr: pyoz.BufferViewMut(f64), factor: f64) void {
///     for (arr.data) |*v| v.* *= factor;
/// }
/// ```
///
/// Python usage:
/// ```python
/// import numpy as np
/// arr = np.array([1.0, 2.0, 3.0], dtype=np.float64)
/// mymodule.scale_array(arr, 2.0)  # Modifies arr in-place!
/// print(arr)  # [2.0, 4.0, 6.0]
/// ```
pub fn BufferViewMut(comptime T: type) type {
    return struct {
        const _is_pyoz_buffer = true;

        /// The underlying data as a mutable Zig slice
        data: []T,
        /// Number of dimensions
        ndim: usize,
        /// Shape of each dimension
        shape: []const Py_ssize_t,
        /// Strides for each dimension (in bytes)
        strides: ?[]const Py_ssize_t,
        /// The Python object (for reference counting)
        _py_obj: *PyObject,
        /// The buffer view (must be released)
        _buffer: py.Py_buffer,

        const Self = @This();
        pub const ElementType = T;
        pub const is_buffer_view = true;
        pub const is_mutable = true;

        /// Get the total number of elements
        pub fn len(self: Self) usize {
            return self.data.len;
        }

        /// Check if the buffer is empty
        pub fn isEmpty(self: Self) bool {
            return self.data.len == 0;
        }

        /// Check if the buffer is C-contiguous
        pub fn isContiguous(self: Self) bool {
            return self._buffer.strides == null or self.ndim == 1;
        }

        /// Get element at a flat index
        pub fn get(self: Self, index: usize) T {
            return self.data[index];
        }

        /// Set element at a flat index
        pub fn set(self: Self, index: usize, value: T) void {
            self.data[index] = value;
        }

        /// Get element at 2D index (row, col)
        pub fn get2D(self: Self, row: usize, col: usize) T {
            if (self.ndim != 2) @panic("get2D requires 2D array");
            if (self.strides) |strd| {
                const byte_offset = @as(usize, @intCast(strd[0])) * row + @as(usize, @intCast(strd[1])) * col;
                const ptr: [*]T = @ptrCast(@alignCast(self._buffer.buf.?));
                const byte_ptr: [*]u8 = @ptrCast(ptr);
                return @as(*T, @ptrCast(@alignCast(byte_ptr + byte_offset))).*;
            } else {
                const cols_count: usize = @intCast(self.shape[1]);
                return self.data[row * cols_count + col];
            }
        }

        /// Set element at 2D index (row, col)
        pub fn set2D(self: Self, row: usize, col: usize, value: T) void {
            if (self.ndim != 2) @panic("set2D requires 2D array");
            if (self.strides) |strd| {
                const byte_offset = @as(usize, @intCast(strd[0])) * row + @as(usize, @intCast(strd[1])) * col;
                const ptr: [*]T = @ptrCast(@alignCast(self._buffer.buf.?));
                const byte_ptr: [*]u8 = @ptrCast(ptr);
                @as(*T, @ptrCast(@alignCast(byte_ptr + byte_offset))).* = value;
            } else {
                const cols_count: usize = @intCast(self.shape[1]);
                self.data[row * cols_count + col] = value;
            }
        }

        /// Get the shape
        pub fn getShape(self: Self) []const Py_ssize_t {
            return self.shape;
        }

        /// Get number of rows (for 2D arrays)
        pub fn rows(self: Self) usize {
            if (self.ndim < 1) return 0;
            return @intCast(self.shape[0]);
        }

        /// Get number of columns (for 2D arrays)
        pub fn cols(self: Self) usize {
            if (self.ndim < 2) return self.len();
            return @intCast(self.shape[1]);
        }

        /// Fill the entire buffer with a value
        pub fn fill(self: Self, value: T) void {
            for (self.data) |*elem| {
                elem.* = value;
            }
        }

        /// Release the buffer - called automatically by the wrapper
        pub fn release(self: *Self) void {
            py.PyBuffer_Release(&self._buffer);
        }
    };
}

/// Get the expected buffer format character for a Zig type
pub fn getBufferFormat(comptime T: type) []const u8 {
    return switch (T) {
        f64 => "d",
        f32 => "f",
        i64 => "q",
        u64 => "Q",
        i32 => "i",
        u32 => "I",
        i16 => "h",
        u16 => "H",
        i8 => "b",
        u8 => "B",
        Complex => "Zd", // complex128 (two f64)
        Complex32 => "Zf", // complex64 (two f32)
        else => @compileError("Unsupported buffer element type: " ++ @typeName(T)),
    };
}

/// Check if a buffer format matches the expected type
pub fn checkBufferFormat(comptime T: type, format: ?[*:0]const u8) bool {
    if (format) |fmt| {
        const fmt_slice = std.mem.sliceTo(fmt, 0);
        if (fmt_slice.len == 0) return false;

        // Handle platform-specific and complex format codes
        return switch (T) {
            // Platform-specific: numpy uses 'l' for int64 on some platforms instead of 'q'
            i64 => fmt_slice.len >= 1 and (fmt_slice[fmt_slice.len - 1] == 'q' or fmt_slice[fmt_slice.len - 1] == 'l'),
            u64 => fmt_slice.len >= 1 and (fmt_slice[fmt_slice.len - 1] == 'Q' or fmt_slice[fmt_slice.len - 1] == 'L'),
            // Complex types: format is "Zd" (complex128) or "Zf" (complex64)
            Complex => std.mem.eql(u8, fmt_slice, "Zd"),
            Complex32 => std.mem.eql(u8, fmt_slice, "Zf"),
            else => {
                const expected = getBufferFormat(T);
                return fmt_slice.len >= 1 and fmt_slice[fmt_slice.len - 1] == expected[0];
            },
        };
    }
    return false;
}
