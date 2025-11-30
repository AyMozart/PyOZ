//! Object operations for Python C API

const types = @import("types.zig");
const c = types.c;
const abi = @import("../abi.zig");
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const Py_ssize_t = types.Py_ssize_t;

// ============================================================================
// Object operations
// ============================================================================

pub inline fn PyObject_Init(obj: *PyObject, type_obj: *PyTypeObject) ?*PyObject {
    return c.PyObject_Init(obj, type_obj);
}

pub inline fn PyObject_New(comptime T: type, type_obj: *PyTypeObject) ?*T {
    // In ABI3 mode, tp_basicsize is not accessible (opaque type)
    // Use compile-time known size instead
    const alloc_size = if (comptime abi.abi3_enabled)
        @sizeOf(T)
    else blk: {
        // Use type's tp_basicsize for allocation - this is important for subclasses
        // which may have larger basicsize to accommodate __dict__ and __weakref__
        const size: usize = @intCast(type_obj.tp_basicsize);
        break :blk @max(size, @sizeOf(T));
    };
    const obj = c.PyObject_Malloc(alloc_size);
    if (obj == null) return null;
    const typed: *T = @ptrCast(@alignCast(obj));
    if (c.PyObject_Init(@ptrCast(typed), type_obj) == null) {
        c.PyObject_Free(obj);
        return null;
    }
    return typed;
}

pub inline fn PyObject_Del(obj: anytype) void {
    c.PyObject_Free(@ptrCast(obj));
}

pub inline fn PyObject_ClearWeakRefs(obj: *PyObject) void {
    c.PyObject_ClearWeakRefs(obj);
}

pub inline fn PyObject_Repr(obj: *PyObject) ?*PyObject {
    return c.PyObject_Repr(obj);
}

pub inline fn PyObject_Str(obj: *PyObject) ?*PyObject {
    return c.PyObject_Str(obj);
}

/// Call a callable object with arguments
pub inline fn PyObject_CallObject(callable: *PyObject, args: ?*PyObject) ?*PyObject {
    return c.PyObject_CallObject(callable, args);
}

/// Call a callable object with args and kwargs
pub inline fn PyObject_Call(callable: *PyObject, args: *PyObject, kwargs: ?*PyObject) ?*PyObject {
    return c.PyObject_Call(callable, args, kwargs);
}

pub inline fn PyObject_SetAttrString(obj: *PyObject, name: [*:0]const u8, value: *PyObject) c_int {
    return c.PyObject_SetAttrString(obj, name, value);
}

pub inline fn PyObject_GenericGetAttr(obj: ?*PyObject, name: ?*PyObject) ?*PyObject {
    return @ptrCast(c.PyObject_GenericGetAttr(@ptrCast(obj), @ptrCast(name)));
}

pub inline fn PyObject_GenericSetAttr(obj: ?*PyObject, name: ?*PyObject, value: ?*PyObject) c_int {
    return c.PyObject_GenericSetAttr(@ptrCast(obj), @ptrCast(name), @ptrCast(value));
}

pub inline fn PyObject_IsTrue(obj: *PyObject) c_int {
    return c.PyObject_IsTrue(obj);
}

/// Get an attribute from an object
pub inline fn PyObject_GetAttr(obj: *PyObject, name: *PyObject) ?*PyObject {
    return c.PyObject_GetAttr(obj, name);
}

/// Get an attribute from an object by name string
pub inline fn PyObject_GetAttrString(obj: *PyObject, name: [*:0]const u8) ?*PyObject {
    return c.PyObject_GetAttrString(obj, name);
}

/// Set an attribute on an object
pub inline fn PyObject_SetAttr(obj: *PyObject, name: *PyObject, value: *PyObject) c_int {
    return c.PyObject_SetAttr(obj, name, value);
}

/// Check if object is an instance of a class
pub inline fn PyObject_IsInstance(obj: *PyObject, cls: *PyObject) c_int {
    return c.PyObject_IsInstance(obj, cls);
}

/// Call a Python callable with arguments
pub inline fn PyObject_CallFunction(callable: *PyObject, args: ?*PyObject) ?*PyObject {
    return c.PyObject_CallObject(callable, args);
}
