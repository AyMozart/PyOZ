//! PyWrapper struct builder for class generation
//!
//! Provides the PyWrapper extern struct that wraps Zig data in a Python object.

const py = @import("../python.zig");

/// Build the PyWrapper struct for a given Zig type T
pub fn WrapperBuilder(
    comptime T: type,
    comptime is_builtin_subclass: bool,
    comptime has_dict_support: bool,
    comptime has_weakref_support: bool,
) type {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;
    _ = fields;

    // Size calculations
    const DataSize = @sizeOf(T);
    const DataAlign = if (DataSize == 0) 1 else @alignOf(T);

    const ptr_size = @sizeOf(?*py.PyObject);
    const dict_size = if (has_dict_support) ptr_size else 0;
    const weakref_size = if (has_weakref_support) ptr_size else 0;
    const extra_size = dict_size + weakref_size;

    const dict_offset: usize = 0;
    const weakref_offset: usize = dict_size;

    const ExtraAlign = if (extra_size > 0) @alignOf(?*py.PyObject) else 1;

    return struct {
        pub const PyWrapper = extern struct {
            ob_base: py.PyObject,
            _data_storage: if (is_builtin_subclass) [0]u8 else [DataSize]u8 align(DataAlign),
            _extra: [extra_size]u8 align(ExtraAlign),

            pub fn getData(self: *@This()) *T {
                if (is_builtin_subclass) return @ptrCast(self);
                return @ptrCast(@alignCast(&self._data_storage));
            }

            pub fn getDataConst(self: *const @This()) *const T {
                if (is_builtin_subclass) return @ptrCast(self);
                return @ptrCast(@alignCast(&self._data_storage));
            }

            pub fn getDict(self: *@This()) ?*py.PyObject {
                if (!has_dict_support) return null;
                const ptr: *?*py.PyObject = @ptrCast(@alignCast(&self._extra[dict_offset]));
                return ptr.*;
            }

            pub fn setDict(self: *@This(), dict: ?*py.PyObject) void {
                if (!has_dict_support) return;
                const ptr: *?*py.PyObject = @ptrCast(@alignCast(&self._extra[dict_offset]));
                ptr.* = dict;
            }

            pub fn getWeakRefList(self: *@This()) ?*py.PyObject {
                if (!has_weakref_support) return null;
                const ptr: *?*py.PyObject = @ptrCast(@alignCast(&self._extra[weakref_offset]));
                return ptr.*;
            }

            pub fn setWeakRefList(self: *@This(), list: ?*py.PyObject) void {
                if (!has_weakref_support) return;
                const ptr: *?*py.PyObject = @ptrCast(@alignCast(&self._extra[weakref_offset]));
                ptr.* = list;
            }

            pub fn initExtra(self: *@This()) void {
                if (has_dict_support) self.setDict(null);
                if (has_weakref_support) self.setWeakRefList(null);
            }
        };

        // Offsets for type object
        pub const dict_struct_offset: py.Py_ssize_t = if (has_dict_support)
            @intCast(@offsetOf(PyWrapper, "_extra") + dict_offset)
        else
            0;

        pub const weakref_struct_offset: py.Py_ssize_t = if (has_weakref_support)
            @intCast(@offsetOf(PyWrapper, "_extra") + weakref_offset)
        else
            0;
    };
}
