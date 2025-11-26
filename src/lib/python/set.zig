//! Set operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// Set operations
// ============================================================================

pub inline fn PySet_New(iterable: ?*PyObject) ?*PyObject {
    return c.PySet_New(iterable);
}

pub inline fn PyFrozenSet_New(iterable: ?*PyObject) ?*PyObject {
    return c.PyFrozenSet_New(iterable);
}

pub inline fn PySet_Size(obj: *PyObject) Py_ssize_t {
    return c.PySet_Size(obj);
}

pub inline fn PySet_Contains(obj: *PyObject, key: *PyObject) c_int {
    return c.PySet_Contains(obj, key);
}

pub inline fn PySet_Add(obj: *PyObject, key: *PyObject) c_int {
    return c.PySet_Add(obj, key);
}

pub inline fn PySet_Discard(obj: *PyObject, key: *PyObject) c_int {
    return c.PySet_Discard(obj, key);
}

pub inline fn PySet_Pop(obj: *PyObject) ?*PyObject {
    return c.PySet_Pop(obj);
}

pub inline fn PySet_Clear(obj: *PyObject) c_int {
    return c.PySet_Clear(obj);
}
