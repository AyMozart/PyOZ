//! Iterator protocol operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;

// ============================================================================
// Iterator protocol
// ============================================================================

/// Get an iterator from any iterable object.
/// Returns null and sets a Python exception if the object is not iterable.
pub inline fn PyObject_GetIter(obj: *PyObject) ?*PyObject {
    return c.PyObject_GetIter(obj);
}

/// Get the next item from an iterator.
/// Returns null when the iterator is exhausted (StopIteration) or on error.
/// Check PyErr_Occurred() to distinguish between exhaustion and error.
pub inline fn PyIter_Next(iter: *PyObject) ?*PyObject {
    return c.PyIter_Next(iter);
}

/// Check if an object is an iterator (has tp_iternext slot).
/// Note: This checks if the object IS an iterator, not if it's iterable.
/// An iterable can produce an iterator via __iter__, but may not be an iterator itself.
pub inline fn PyIter_Check(obj: *PyObject) bool {
    // An object is an iterator if its type has tp_iternext defined
    // We check this by seeing if the type has __next__ method
    const tp = Py_TYPE(obj);
    return tp.tp_iternext != null;
}

/// Check if an object is iterable (can produce an iterator).
/// Returns true if the object has __iter__ method or is a sequence.
pub inline fn PyObject_IsIterable(obj: *PyObject) bool {
    // Try to get an iterator - if it succeeds, the object is iterable
    const iter = c.PyObject_GetIter(obj);
    if (iter) |it| {
        c.Py_DecRef(it);
        return true;
    }
    // Clear any exception that was set
    c.PyErr_Clear();
    return false;
}

/// Get the type of a Python object
inline fn Py_TYPE(obj: *PyObject) *c.PyTypeObject {
    return @ptrCast(obj.ob_type);
}

// ============================================================================
// Sequence operations
// ============================================================================

pub inline fn PySequence_List(obj: *PyObject) ?*PyObject {
    return c.PySequence_List(obj);
}
