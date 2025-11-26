//! Reference counting operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;

// ============================================================================
// Reference counting
// ============================================================================

pub inline fn Py_IncRef(obj: ?*PyObject) void {
    c.Py_IncRef(obj);
}

pub inline fn Py_DecRef(obj: ?*PyObject) void {
    c.Py_DecRef(obj);
}
