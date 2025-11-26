//! String operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// String creation
// ============================================================================

pub inline fn PyUnicode_FromString(s: [*:0]const u8) ?*PyObject {
    return c.PyUnicode_FromString(s);
}

pub inline fn PyUnicode_FromStringAndSize(s: [*]const u8, size: Py_ssize_t) ?*PyObject {
    return c.PyUnicode_FromStringAndSize(s, size);
}

// ============================================================================
// String extraction
// ============================================================================

pub inline fn PyUnicode_AsUTF8(obj: *PyObject) ?[*:0]const u8 {
    return c.PyUnicode_AsUTF8(obj);
}

pub inline fn PyUnicode_AsUTF8AndSize(obj: *PyObject, size: *Py_ssize_t) ?[*]const u8 {
    return c.PyUnicode_AsUTF8AndSize(obj, size);
}

// ============================================================================
// String formatting
// ============================================================================

pub inline fn PyUnicode_FromFormat(format: [*:0]const u8, args: anytype) ?*PyObject {
    return @call(.auto, c.PyUnicode_FromFormat, .{format} ++ args);
}
