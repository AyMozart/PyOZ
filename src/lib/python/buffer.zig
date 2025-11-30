//! Buffer protocol operations for Python C API
//!
//! NOTE: The buffer protocol (Py_buffer, PyObject_GetBuffer, etc.) is NOT part
//! of the Python Stable ABI (Limited API). This entire module is unavailable
//! in ABI3 mode.

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;

/// Whether buffer protocol is available (not in ABI3 mode)
pub const available = !types.abi3_enabled;

// ============================================================================
// Buffer protocol types and flags
// ============================================================================

// In ABI3 mode, these types don't exist in the headers, so we define dummy types
// that will cause compile errors if used (via the guard functions below)
pub const Py_buffer = if (available) c.Py_buffer else opaque {};
pub const PyBufferProcs = if (available) c.PyBufferProcs else opaque {};

pub const PyBUF_SIMPLE: c_int = if (available) c.PyBUF_SIMPLE else 0;
pub const PyBUF_WRITABLE: c_int = if (available) c.PyBUF_WRITABLE else 0;
pub const PyBUF_FORMAT: c_int = if (available) c.PyBUF_FORMAT else 0;
pub const PyBUF_ND: c_int = if (available) c.PyBUF_ND else 0;
pub const PyBUF_STRIDES: c_int = if (available) c.PyBUF_STRIDES else 0;

/// Additional buffer flags for numpy compatibility
pub const PyBUF_C_CONTIGUOUS: c_int = if (available) c.PyBUF_C_CONTIGUOUS else 0;
pub const PyBUF_F_CONTIGUOUS: c_int = if (available) c.PyBUF_F_CONTIGUOUS else 0;
pub const PyBUF_ANY_CONTIGUOUS: c_int = if (available) c.PyBUF_ANY_CONTIGUOUS else 0;
pub const PyBUF_FULL: c_int = if (available) c.PyBUF_FULL else 0;
pub const PyBUF_FULL_RO: c_int = if (available) c.PyBUF_FULL_RO else 0;

// ============================================================================
// ABI3 compile-time guard
// ============================================================================

const abi3_error_msg =
    \\The buffer protocol (Py_buffer, PyObject_GetBuffer, BufferView, etc.) is NOT
    \\part of the Python Stable ABI (Limited API).
    \\
    \\This means you cannot use BufferView(T) or BufferViewMut(T) to read numpy
    \\arrays or other buffer objects in ABI3 mode.
    \\
    \\Workarounds:
    \\  - Use lists instead of numpy arrays
    \\  - Convert numpy arrays to lists in Python before passing to Zig
    \\  - Set abi3 = false in your build configuration
;

fn requireBufferApi() void {
    if (!available) {
        @compileError(abi3_error_msg);
    }
}

// ============================================================================
// Buffer protocol functions
// ============================================================================

pub inline fn PyBuffer_FillInfo(view: *Py_buffer, obj: ?*PyObject, buf: ?*anyopaque, len: Py_ssize_t, readonly: c_int, flags: c_int) c_int {
    comptime requireBufferApi();
    return c.PyBuffer_FillInfo(view, obj, buf, len, readonly, flags);
}

/// Get a buffer view from an object that supports the buffer protocol (e.g., numpy arrays, bytes, memoryview)
/// Returns 0 on success, -1 on failure
/// Caller MUST call PyBuffer_Release when done with the buffer
pub inline fn PyObject_GetBuffer(obj: *PyObject, view: *Py_buffer, flags: c_int) c_int {
    comptime requireBufferApi();
    return c.PyObject_GetBuffer(obj, view, flags);
}

/// Release a buffer obtained via PyObject_GetBuffer
pub inline fn PyBuffer_Release(view: *Py_buffer) void {
    comptime requireBufferApi();
    c.PyBuffer_Release(view);
}

/// Check if an object supports the buffer protocol
pub inline fn PyObject_CheckBuffer(obj: *PyObject) bool {
    comptime requireBufferApi();
    return c.PyObject_CheckBuffer(obj) != 0;
}
