//! Module operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const PyModuleDef = types.PyModuleDef;

// ============================================================================
// Module creation
// ============================================================================

pub inline fn PyModule_Create(def: *PyModuleDef) ?*PyObject {
    return c.PyModule_Create2(def, c.PYTHON_API_VERSION);
}

pub inline fn PyModule_AddObject(module: *PyObject, name: [*:0]const u8, value: *PyObject) c_int {
    return c.PyModule_AddObject(module, name, value);
}

pub inline fn PyModule_AddIntConstant(module: *PyObject, name: [*:0]const u8, value: c_long) c_int {
    return c.PyModule_AddIntConstant(module, name, value);
}

pub inline fn PyModule_AddStringConstant(module: *PyObject, name: [*:0]const u8, value: [*:0]const u8) c_int {
    return c.PyModule_AddStringConstant(module, name, value);
}

pub inline fn PyModule_AddType(module: *PyObject, type_obj: *PyTypeObject) c_int {
    return c.PyModule_AddType(module, type_obj);
}

/// Get the dictionary of a module
pub inline fn PyModule_GetDict(module: *PyObject) ?*PyObject {
    return c.PyModule_GetDict(module);
}
