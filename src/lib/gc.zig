//! Garbage Collection support types
//!
//! Provides GCVisitor for implementing __traverse__ in classes that
//! hold references to Python objects.

const py = @import("python.zig");
const PyObject = py.PyObject;

/// Visitor for GC traversal - use in __traverse__ to visit PyObject references
/// Usage in __traverse__:
///   pub fn __traverse__(self: *MyClass, visitor: pyoz.GCVisitor) c_int {
///       var ret = visitor.call(self.some_py_object);
///       if (ret != 0) return ret;
///       return 0;
///   }
pub const GCVisitor = struct {
    visit: *const fn (?*PyObject, ?*anyopaque) callconv(.c) c_int,
    arg: ?*anyopaque,

    /// Visit a PyObject reference - call this for each Python object your class holds
    pub fn call(self: GCVisitor, obj: ?*PyObject) c_int {
        if (obj) |o| {
            return self.visit(o, self.arg);
        }
        return 0;
    }
};
