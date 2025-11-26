//! Repr/str/hash protocol for class generation
//!
//! Implements __repr__, __str__, __hash__

const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

fn getConversions() type {
    return conversion.Conversions;
}

/// Build repr protocol for a given type
pub fn ReprProtocol(comptime T: type, comptime Parent: type, comptime name: [*:0]const u8) type {
    return struct {
        /// Default __repr__
        pub fn py_repr(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            _ = self;
            return py.PyUnicode_FromString(name);
        }

        /// Custom __repr__ - calls T.__repr__
        pub fn py_magic_repr(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__repr__(self.getDataConst());
            return getConversions().toPy(@TypeOf(result), result);
        }

        /// Custom __str__ - calls T.__str__
        pub fn py_magic_str(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__str__(self.getDataConst());
            return getConversions().toPy(@TypeOf(result), result);
        }

        /// Custom __hash__ - calls T.__hash__
        pub fn py_hash(self_obj: ?*py.PyObject) callconv(.c) py.c.Py_hash_t {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            return @intCast(T.__hash__(self.getDataConst()));
        }
    };
}
