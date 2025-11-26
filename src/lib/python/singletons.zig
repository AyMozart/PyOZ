//! Python singleton objects
//!
//! None, True, False, NotImplemented

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const refcount = @import("refcount.zig");
const Py_IncRef = refcount.Py_IncRef;

// ============================================================================
// Singletons - MUST increment refcount when returning these!
// ============================================================================

pub inline fn Py_None() *PyObject {
    return @ptrCast(&c._Py_NoneStruct);
}

pub inline fn Py_True() *PyObject {
    return @ptrCast(&c._Py_TrueStruct);
}

pub inline fn Py_False() *PyObject {
    return @ptrCast(&c._Py_FalseStruct);
}

/// Return None with proper reference counting (use this when returning from functions)
pub inline fn Py_RETURN_NONE() *PyObject {
    const none = Py_None();
    Py_IncRef(none);
    return none;
}

/// Return True with proper reference counting
pub inline fn Py_RETURN_TRUE() *PyObject {
    const t = Py_True();
    Py_IncRef(t);
    return t;
}

/// Return False with proper reference counting
pub inline fn Py_RETURN_FALSE() *PyObject {
    const f = Py_False();
    Py_IncRef(f);
    return f;
}

/// Return a boolean with proper reference counting
pub inline fn Py_RETURN_BOOL(val: bool) *PyObject {
    return if (val) Py_RETURN_TRUE() else Py_RETURN_FALSE();
}

/// Return NotImplemented (for comparison operators)
pub inline fn Py_NotImplemented() *PyObject {
    const ni = @as(*PyObject, @ptrCast(&c._Py_NotImplementedStruct));
    Py_IncRef(ni);
    return ni;
}
