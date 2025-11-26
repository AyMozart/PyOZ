//! Dict operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// Dict operations
// ============================================================================

pub inline fn PyDict_New() ?*PyObject {
    return c.PyDict_New();
}

pub inline fn PyDict_SetItemString(obj: *PyObject, key: [*:0]const u8, val: *PyObject) c_int {
    return c.PyDict_SetItemString(obj, key, val);
}

pub inline fn PyDict_GetItemString(obj: *PyObject, key: [*:0]const u8) ?*PyObject {
    return c.PyDict_GetItemString(obj, key);
}

pub inline fn PyDict_Size(obj: *PyObject) Py_ssize_t {
    return c.PyDict_Size(obj);
}

pub inline fn PyDict_Keys(obj: *PyObject) ?*PyObject {
    return c.PyDict_Keys(obj);
}

pub inline fn PyDict_Values(obj: *PyObject) ?*PyObject {
    return c.PyDict_Values(obj);
}

pub inline fn PyDict_Items(obj: *PyObject) ?*PyObject {
    return c.PyDict_Items(obj);
}

pub inline fn PyDict_SetItem(obj: *PyObject, key: *PyObject, val: *PyObject) c_int {
    return c.PyDict_SetItem(obj, key, val);
}

pub inline fn PyDict_GetItem(obj: *PyObject, key: *PyObject) ?*PyObject {
    return c.PyDict_GetItem(obj, key);
}

pub inline fn PyDict_Next(obj: *PyObject, pos: *Py_ssize_t, key: *?*PyObject, value: *?*PyObject) c_int {
    return c.PyDict_Next(obj, pos, key, value);
}
