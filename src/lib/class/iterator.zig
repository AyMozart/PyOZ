//! Iterator protocol for class generation
//!
//! Implements __iter__, __next__

const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

fn getConversions() type {
    return conversion.Conversions;
}

fn getSelfAwareConverter(comptime T: type) type {
    return conversion.Converter(&[_]type{T});
}

/// Build iterator protocol for a given type
pub fn IteratorProtocol(comptime T: type, comptime Parent: type) type {
    const Conv = getSelfAwareConverter(T);

    return struct {
        pub fn py_iter(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__iter__(self.getData());
            const ResultType = @TypeOf(result);

            const result_info = @typeInfo(ResultType);
            if (result_info == .pointer and result_info.pointer.child == T) {
                py.Py_IncRef(self_obj);
                return self_obj;
            } else {
                return Conv.toPy(ResultType, result);
            }
        }

        pub fn py_iternext(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__next__(self.getData());
            if (result) |value| {
                return getConversions().toPy(@TypeOf(value), value);
            } else {
                return null;
            }
        }
    };
}
