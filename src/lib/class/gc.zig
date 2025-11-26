//! Garbage collection support for class generation
//!
//! Implements __traverse__ and __clear__ for cyclic garbage collection

const std = @import("std");
const py = @import("../python.zig");
const gc_mod = @import("../gc.zig");

/// Build GC protocol for a given type
pub fn GCBuilder(comptime T: type, comptime PyWrapper: type) type {
    return struct {
        /// Check if this type has GC support
        pub fn hasGCSupport() bool {
            return @hasDecl(T, "__traverse__");
        }

        /// tp_traverse: Called by GC to discover references
        pub fn py_traverse(self_obj: ?*py.PyObject, visit: *const fn (?*py.PyObject, ?*anyopaque) callconv(.c) c_int, arg: ?*anyopaque) callconv(.c) c_int {
            if (self_obj == null) return 0;

            const self_ptr: *PyWrapper = @ptrCast(@alignCast(self_obj.?));
            const self = self_ptr.getData();

            // Create visitor struct
            const visitor = gc_mod.GCVisitor{ .visit = visit, .arg = arg };

            // Call user's __traverse__ with the visitor
            if (@hasDecl(T, "__traverse__")) {
                return T.__traverse__(self, visitor);
            }
            return 0;
        }

        /// tp_clear: Called by GC to break reference cycles
        pub fn py_clear(self_obj: ?*py.PyObject) callconv(.c) c_int {
            if (self_obj == null) return 0;

            const self_ptr: *PyWrapper = @ptrCast(@alignCast(self_obj.?));
            const self = self_ptr.getData();

            // Call user's __clear__
            if (@hasDecl(T, "__clear__")) {
                T.__clear__(self);
            }
            return 0;
        }
    };
}
