//! Bytes/ByteArray operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// Bytes operations
// ============================================================================

pub inline fn PyBytes_FromStringAndSize(str: [*]const u8, size: Py_ssize_t) ?*PyObject {
    return c.PyBytes_FromStringAndSize(str, size);
}

pub inline fn PyBytes_AsStringAndSize(obj: *PyObject, buffer: *[*]u8, length: *Py_ssize_t) c_int {
    return c.PyBytes_AsStringAndSize(obj, @ptrCast(buffer), length);
}

pub inline fn PyBytes_Size(obj: *PyObject) Py_ssize_t {
    return c.PyBytes_Size(obj);
}

pub inline fn PyBytes_AsString(obj: *PyObject) ?[*]u8 {
    return c.PyBytes_AsString(obj);
}

// ============================================================================
// ByteArray operations
// ============================================================================

pub inline fn PyByteArray_FromStringAndSize(str: ?[*]const u8, size: Py_ssize_t) ?*PyObject {
    return c.PyByteArray_FromStringAndSize(str, size);
}

pub inline fn PyByteArray_AsString(obj: *PyObject) ?[*]u8 {
    return c.PyByteArray_AsString(obj);
}

pub inline fn PyByteArray_Size(obj: *PyObject) Py_ssize_t {
    return c.PyByteArray_Size(obj);
}
