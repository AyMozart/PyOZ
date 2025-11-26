//! Buffer protocol operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// Buffer protocol types and flags
// ============================================================================

pub const Py_buffer = c.Py_buffer;
pub const PyBufferProcs = c.PyBufferProcs;
pub const PyBUF_SIMPLE: c_int = c.PyBUF_SIMPLE;
pub const PyBUF_WRITABLE: c_int = c.PyBUF_WRITABLE;
pub const PyBUF_FORMAT: c_int = c.PyBUF_FORMAT;
pub const PyBUF_ND: c_int = c.PyBUF_ND;
pub const PyBUF_STRIDES: c_int = c.PyBUF_STRIDES;

/// Additional buffer flags for numpy compatibility
pub const PyBUF_C_CONTIGUOUS: c_int = c.PyBUF_C_CONTIGUOUS;
pub const PyBUF_F_CONTIGUOUS: c_int = c.PyBUF_F_CONTIGUOUS;
pub const PyBUF_ANY_CONTIGUOUS: c_int = c.PyBUF_ANY_CONTIGUOUS;
pub const PyBUF_FULL: c_int = c.PyBUF_FULL;
pub const PyBUF_FULL_RO: c_int = c.PyBUF_FULL_RO;

// ============================================================================
// Buffer protocol functions
// ============================================================================

pub inline fn PyBuffer_FillInfo(view: *Py_buffer, obj: ?*PyObject, buf: ?*anyopaque, len: Py_ssize_t, readonly: c_int, flags: c_int) c_int {
    return c.PyBuffer_FillInfo(view, obj, buf, len, readonly, flags);
}

/// Get a buffer view from an object that supports the buffer protocol (e.g., numpy arrays, bytes, memoryview)
/// Returns 0 on success, -1 on failure
/// Caller MUST call PyBuffer_Release when done with the buffer
pub inline fn PyObject_GetBuffer(obj: *PyObject, view: *Py_buffer, flags: c_int) c_int {
    return c.PyObject_GetBuffer(obj, view, flags);
}

/// Release a buffer obtained via PyObject_GetBuffer
pub inline fn PyBuffer_Release(view: *Py_buffer) void {
    c.PyBuffer_Release(view);
}

/// Check if an object supports the buffer protocol
pub inline fn PyObject_CheckBuffer(obj: *PyObject) bool {
    return c.PyObject_CheckBuffer(obj) != 0;
}
