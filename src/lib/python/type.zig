//! Type operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const PyType_Spec = types.PyType_Spec;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// Type operations
// ============================================================================

pub inline fn PyType_FromSpec(spec: *PyType_Spec) ?*PyObject {
    return c.PyType_FromSpec(spec);
}

pub inline fn PyType_Ready(type_obj: *PyTypeObject) c_int {
    return c.PyType_Ready(type_obj);
}

pub inline fn PyType_GenericAlloc(type_obj: *PyTypeObject, nitems: Py_ssize_t) ?*PyObject {
    return c.PyType_GenericAlloc(type_obj, nitems);
}

pub inline fn PyType_GenericNew(type_obj: *PyTypeObject, args: ?*PyObject, kwds: ?*PyObject) ?*PyObject {
    return c.PyType_GenericNew(type_obj, args, kwds);
}
