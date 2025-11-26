//! Tuple operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;
const refcount = @import("refcount.zig");
const Py_IncRef = refcount.Py_IncRef;

// ============================================================================
// Tuple operations
// ============================================================================

pub inline fn PyTuple_Size(obj: *PyObject) Py_ssize_t {
    return c.PyTuple_Size(obj);
}

pub inline fn PyTuple_GetItem(obj: *PyObject, pos: Py_ssize_t) ?*PyObject {
    return c.PyTuple_GetItem(obj, pos);
}

pub inline fn PyTuple_New(size: Py_ssize_t) ?*PyObject {
    return c.PyTuple_New(size);
}

pub inline fn PyTuple_SetItem(obj: *PyObject, pos: Py_ssize_t, item: *PyObject) c_int {
    return c.PyTuple_SetItem(obj, pos, item);
}

/// Create a tuple from a comptime-known tuple of PyObject pointers
pub fn PyTuple_Pack(args: anytype) ?*PyObject {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("Expected tuple argument");
    }
    const n = args_info.@"struct".fields.len;
    const tuple = PyTuple_New(n) orelse return null;
    inline for (0..n) |i| {
        const item: *PyObject = args[i];
        Py_IncRef(item); // SetItem steals reference
        _ = PyTuple_SetItem(tuple, @intCast(i), item);
    }
    return tuple;
}
