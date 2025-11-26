//! Error handling operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;

// ============================================================================
// Error handling
// ============================================================================

pub inline fn PyErr_SetString(exc: *PyObject, msg: [*:0]const u8) void {
    c.PyErr_SetString(exc, msg);
}

pub inline fn PyErr_Occurred() ?*PyObject {
    return c.PyErr_Occurred();
}

pub inline fn PyErr_Clear() void {
    c.PyErr_Clear();
}

pub inline fn PyErr_ExceptionMatches(exc: *PyObject) c_int {
    return c.PyErr_ExceptionMatches(@ptrCast(exc));
}

/// Fetch the current exception (type, value, traceback)
/// Clears the exception state. Caller owns the references.
pub inline fn PyErr_Fetch(ptype: *?*PyObject, pvalue: *?*PyObject, ptraceback: *?*PyObject) void {
    c.PyErr_Fetch(@ptrCast(ptype), @ptrCast(pvalue), @ptrCast(ptraceback));
}

/// Restore a previously fetched exception
pub inline fn PyErr_Restore(ptype: ?*PyObject, pvalue: ?*PyObject, ptraceback: ?*PyObject) void {
    c.PyErr_Restore(ptype, pvalue, ptraceback);
}

/// Normalize an exception (ensures value is an instance of type)
pub inline fn PyErr_NormalizeException(ptype: *?*PyObject, pvalue: *?*PyObject, ptraceback: *?*PyObject) void {
    c.PyErr_NormalizeException(@ptrCast(ptype), @ptrCast(pvalue), @ptrCast(ptraceback));
}

/// Check if a given exception matches a specific type
pub inline fn PyErr_GivenExceptionMatches(given: ?*PyObject, exc: *PyObject) bool {
    return c.PyErr_GivenExceptionMatches(given, exc) != 0;
}

/// Set an exception with an object value
pub inline fn PyErr_SetObject(exc: *PyObject, value: *PyObject) void {
    c.PyErr_SetObject(exc, value);
}

/// Get exception info (for except clause use)
pub inline fn PyErr_GetExcInfo(ptype: *?*PyObject, pvalue: *?*PyObject, ptraceback: *?*PyObject) void {
    c.PyErr_GetExcInfo(@ptrCast(ptype), @ptrCast(pvalue), @ptrCast(ptraceback));
}

/// Create a new exception type
pub inline fn PyErr_NewException(name: [*:0]const u8, base: ?*PyObject, dict: ?*PyObject) ?*PyObject {
    return c.PyErr_NewException(name, base, dict);
}

/// Print the current exception to stderr and clear it
pub inline fn PyErr_Print() void {
    c.PyErr_Print();
}

// ============================================================================
// Exception types - accessed via function to avoid comptime issues
// ============================================================================

pub inline fn PyExc_RuntimeError() *PyObject {
    return @ptrCast(c.PyExc_RuntimeError);
}

pub inline fn PyExc_TypeError() *PyObject {
    return @ptrCast(c.PyExc_TypeError);
}

pub inline fn PyExc_ValueError() *PyObject {
    return @ptrCast(c.PyExc_ValueError);
}

pub inline fn PyExc_AttributeError() *PyObject {
    return @ptrCast(c.PyExc_AttributeError);
}

pub inline fn PyExc_IndexError() *PyObject {
    return @ptrCast(c.PyExc_IndexError);
}

pub inline fn PyExc_KeyError() *PyObject {
    return @ptrCast(c.PyExc_KeyError);
}

pub inline fn PyExc_ZeroDivisionError() *PyObject {
    return @ptrCast(c.PyExc_ZeroDivisionError);
}

pub inline fn PyExc_StopIteration() *PyObject {
    return @ptrCast(c.PyExc_StopIteration);
}

pub inline fn PyExc_Exception() *PyObject {
    return @ptrCast(c.PyExc_Exception);
}
