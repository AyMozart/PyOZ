//! Numeric operations for Python C API
//!
//! Includes int, float, bool, and complex operations.

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const Py_ssize_t = types.Py_ssize_t;
const typecheck = @import("typecheck.zig");
const Py_TYPE = typecheck.Py_TYPE;

// ============================================================================
// Object creation functions
// ============================================================================

pub inline fn PyLong_FromLongLong(v: c_longlong) ?*PyObject {
    return c.PyLong_FromLongLong(v);
}

pub inline fn PyLong_FromString(str: [*:0]const u8, pend: [*c][*c]u8, base: c_int) ?*PyObject {
    return c.PyLong_FromString(str, pend, base);
}

pub inline fn PyLong_FromUnsignedLongLong(v: c_ulonglong) ?*PyObject {
    return c.PyLong_FromUnsignedLongLong(v);
}

pub inline fn PyFloat_FromDouble(v: f64) ?*PyObject {
    return c.PyFloat_FromDouble(v);
}

// Complex number creation
pub inline fn PyComplex_FromDoubles(real: f64, imag: f64) ?*PyObject {
    return c.PyComplex_FromDoubles(real, imag);
}

pub inline fn PyComplex_RealAsDouble(obj: *PyObject) f64 {
    return c.PyComplex_RealAsDouble(obj);
}

pub inline fn PyComplex_ImagAsDouble(obj: *PyObject) f64 {
    return c.PyComplex_ImagAsDouble(obj);
}

pub inline fn PyComplex_Check(obj: *PyObject) bool {
    // Reimplemented to avoid cImport issues with _PyObject_CAST_CONST
    const obj_type = Py_TYPE(obj) orelse return false;
    const complex_type: *PyTypeObject = @ptrCast(&c.PyComplex_Type);
    return obj_type == complex_type or c.PyType_IsSubtype(obj_type, complex_type) != 0;
}

pub inline fn PyBool_FromLong(v: c_long) ?*PyObject {
    return c.PyBool_FromLong(v);
}

// ============================================================================
// Object extraction functions
// ============================================================================

pub inline fn PyLong_AsLongLong(obj: *PyObject) c_longlong {
    return c.PyLong_AsLongLong(obj);
}

pub inline fn PyLong_AsUnsignedLongLong(obj: *PyObject) c_ulonglong {
    return c.PyLong_AsUnsignedLongLong(obj);
}

pub inline fn PyLong_AsDouble(obj: *PyObject) f64 {
    return c.PyLong_AsDouble(obj);
}

pub inline fn PyFloat_AsDouble(obj: *PyObject) f64 {
    return c.PyFloat_AsDouble(obj);
}
