//! Mapping protocol for class generation
//!
//! Implements __getitem__, __setitem__, __delitem__ for dict-like access

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

fn getConversions() type {
    return conversion.Conversions;
}

/// Build mapping protocol for a given type
pub fn MappingProtocol(comptime T: type, comptime Parent: type) type {
    return struct {
        pub fn hasMappingMethods() bool {
            return @hasDecl(T, "__getitem__");
        }

        pub var mapping_methods: py.PyMappingMethods = makeMappingMethods();

        fn makeMappingMethods() py.PyMappingMethods {
            var mm: py.PyMappingMethods = std.mem.zeroes(py.PyMappingMethods);

            if (@hasDecl(T, "__len__")) mm.mp_length = @ptrCast(&py_mp_length);
            if (@hasDecl(T, "__getitem__")) mm.mp_subscript = @ptrCast(&py_mp_subscript);
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) mm.mp_ass_subscript = @ptrCast(&py_mp_ass_subscript);

            return mm;
        }

        fn py_mp_length(self_obj: ?*py.PyObject) callconv(.c) py.Py_ssize_t {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const result = T.__len__(self.getDataConst());
            return @intCast(result);
        }

        fn py_mp_subscript(self_obj: ?*py.PyObject, key_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const key = key_obj orelse return null;

            const GetItemFn = @TypeOf(T.__getitem__);
            const fn_info = @typeInfo(GetItemFn).@"fn";
            const KeyType = fn_info.params[1].type.?;

            const is_integer_key = comptime blk: {
                const key_info = @typeInfo(KeyType);
                break :blk key_info == .int or key_info == .comptime_int;
            };

            const zig_key = getConversions().fromPy(KeyType, key) catch {
                if (is_integer_key) {
                    py.PyErr_SetString(py.PyExc_IndexError(), "Invalid index type");
                } else {
                    py.PyErr_SetString(py.PyExc_KeyError(), "Invalid key type");
                }
                return null;
            };

            const GetItemRetType = fn_info.return_type.?;
            if (@typeInfo(GetItemRetType) == .error_union) {
                const result = T.__getitem__(self.getDataConst(), zig_key) catch |err| {
                    const msg = @errorName(err);
                    if (is_integer_key) {
                        py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                    } else {
                        py.PyErr_SetString(py.PyExc_KeyError(), msg.ptr);
                    }
                    return null;
                };
                return getConversions().toPy(@TypeOf(result), result);
            } else {
                const result = T.__getitem__(self.getDataConst(), zig_key);
                return getConversions().toPy(GetItemRetType, result);
            }
        }

        fn py_mp_ass_subscript(self_obj: ?*py.PyObject, key_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const key = key_obj orelse return -1;

            if (value_obj) |value| {
                if (!@hasDecl(T, "__setitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item assignment");
                    return -1;
                }

                const SetItemFn = @TypeOf(T.__setitem__);
                const set_fn_info = @typeInfo(SetItemFn).@"fn";
                const KeyType = set_fn_info.params[1].type.?;
                const ValueType = set_fn_info.params[2].type.?;

                const is_integer_key = comptime blk: {
                    const key_info = @typeInfo(KeyType);
                    break :blk key_info == .int or key_info == .comptime_int;
                };

                const zig_key = getConversions().fromPy(KeyType, key) catch {
                    if (is_integer_key) {
                        py.PyErr_SetString(py.PyExc_IndexError(), "Invalid index type");
                    } else {
                        py.PyErr_SetString(py.PyExc_KeyError(), "Invalid key type");
                    }
                    return -1;
                };

                const zig_value = getConversions().fromPy(ValueType, value) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "invalid value type for __setitem__");
                    return -1;
                };

                const SetRetType = set_fn_info.return_type.?;
                if (@typeInfo(SetRetType) == .error_union) {
                    T.__setitem__(self.getData(), zig_key, zig_value) catch |err| {
                        const msg = @errorName(err);
                        if (is_integer_key) {
                            py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                        } else {
                            py.PyErr_SetString(py.PyExc_KeyError(), msg.ptr);
                        }
                        return -1;
                    };
                } else {
                    T.__setitem__(self.getData(), zig_key, zig_value);
                }
                return 0;
            } else {
                if (!@hasDecl(T, "__delitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item deletion");
                    return -1;
                }

                const DelItemFn = @TypeOf(T.__delitem__);
                const del_fn_info = @typeInfo(DelItemFn).@"fn";
                const KeyType = del_fn_info.params[1].type.?;

                const is_integer_key = comptime blk: {
                    const key_info = @typeInfo(KeyType);
                    break :blk key_info == .int or key_info == .comptime_int;
                };

                const zig_key = getConversions().fromPy(KeyType, key) catch {
                    if (is_integer_key) {
                        py.PyErr_SetString(py.PyExc_IndexError(), "Invalid index type");
                    } else {
                        py.PyErr_SetString(py.PyExc_KeyError(), "Invalid key type");
                    }
                    return -1;
                };

                const DelRetType = del_fn_info.return_type.?;
                if (@typeInfo(DelRetType) == .error_union) {
                    T.__delitem__(self.getData(), zig_key) catch |err| {
                        const msg = @errorName(err);
                        if (is_integer_key) {
                            py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                        } else {
                            py.PyErr_SetString(py.PyExc_KeyError(), msg.ptr);
                        }
                        return -1;
                    };
                } else {
                    T.__delitem__(self.getData(), zig_key);
                }
                return 0;
            }
        }
    };
}
