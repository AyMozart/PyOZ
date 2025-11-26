//! List operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// List operations
// ============================================================================

pub inline fn PyList_New(size: Py_ssize_t) ?*PyObject {
    return c.PyList_New(size);
}

pub inline fn PyList_Size(obj: *PyObject) Py_ssize_t {
    return c.PyList_Size(obj);
}

pub inline fn PyList_GetItem(obj: *PyObject, pos: Py_ssize_t) ?*PyObject {
    return c.PyList_GetItem(obj, pos);
}

pub inline fn PyList_SetItem(obj: *PyObject, pos: Py_ssize_t, item: *PyObject) c_int {
    return c.PyList_SetItem(obj, pos, item);
}

pub inline fn PyList_Append(obj: *PyObject, item: *PyObject) c_int {
    return c.PyList_Append(obj, item);
}

pub inline fn PyList_SetSlice(obj: *PyObject, low: Py_ssize_t, high: Py_ssize_t, itemlist: ?*PyObject) c_int {
    return c.PyList_SetSlice(obj, low, high, itemlist);
}

pub inline fn PyList_Insert(obj: *PyObject, index: Py_ssize_t, item: *PyObject) c_int {
    return c.PyList_Insert(obj, index, item);
}
