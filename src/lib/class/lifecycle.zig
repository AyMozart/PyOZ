//! Object lifecycle functions for class generation
//!
//! Provides py_new, py_init, py_dealloc implementations.

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");
const abi = @import("../abi.zig");

fn getConversions() type {
    return conversion.Conversions;
}

/// Build lifecycle functions for a given type
/// In ABI3 mode, type_object_ptr is not used (we get the type from heap_type at runtime)
pub fn LifecycleBuilder(
    comptime T: type,
    comptime PyWrapper: type,
    comptime type_object_ptr: if (abi.abi3_enabled) ?*anyopaque else *py.PyTypeObject,
    comptime has_dict_support: bool,
    comptime has_weakref_support: bool,
    comptime is_builtin_subclass: bool,
) type {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;

    return struct {
        /// __new__ - allocate object
        pub fn py_new(type_obj: ?*py.PyTypeObject, args: ?*py.PyObject, kwds: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = args;
            _ = kwds;
            const t = type_obj orelse return null;
            const obj = py.PyType_GenericAlloc(t, 0) orelse return null;
            const self: *PyWrapper = @ptrCast(@alignCast(obj));
            self.getData().* = std.mem.zeroes(T);
            self.initExtra();
            return obj;
        }

        /// __init__ - initialize object
        pub fn py_init(self_obj: ?*py.PyObject, args: ?*py.PyObject, kwds: ?*py.PyObject) callconv(.c) c_int {
            _ = kwds;
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const py_args = args orelse {
                if (@hasDecl(T, "__new__")) {
                    const NewFn = @TypeOf(T.__new__);
                    const new_params = @typeInfo(NewFn).@"fn".params;
                    if (new_params.len == 0) {
                        self.getData().* = T.__new__();
                        return 0;
                    }
                }
                if (fields.len == 0) return 0;
                py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                return -1;
            };

            const arg_count = py.PyTuple_Size(py_args);

            if (@hasDecl(T, "__new__")) {
                const NewFn = @TypeOf(T.__new__);
                const new_fn_info = @typeInfo(NewFn).@"fn";
                const new_params = new_fn_info.params;

                if (arg_count != new_params.len) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                    return -1;
                }

                const zig_args = parseNewArgs(py_args) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert arguments");
                    return -1;
                };

                self.getData().* = @call(.auto, T.__new__, zig_args);
                return 0;
            }

            if (arg_count != fields.len) {
                py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                return -1;
            }

            const data = self.getData();
            comptime var i: usize = 0;
            inline for (fields) |field| {
                const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Failed to get argument");
                    return -1;
                };
                @field(data.*, field.name) = getConversions().fromPy(field.type, item) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert argument: " ++ field.name);
                    return -1;
                };
                i += 1;
            }

            return 0;
        }

        fn parseNewArgs(py_args: *py.PyObject) !NewArgsTuple() {
            if (!@hasDecl(T, "__new__")) {
                return error.NoNewFunction;
            }
            const NewFn = @TypeOf(T.__new__);
            const new_params = @typeInfo(NewFn).@"fn".params;

            var result: NewArgsTuple() = undefined;
            inline for (0..new_params.len) |i| {
                const item = py.PyTuple_GetItem(py_args, @intCast(i)) orelse return error.InvalidArgument;
                result[i] = try getConversions().fromPy(new_params[i].type.?, item);
            }
            return result;
        }

        fn NewArgsTuple() type {
            if (!@hasDecl(T, "__new__")) {
                return std.meta.Tuple(&[_]type{});
            }
            const NewFn = @TypeOf(T.__new__);
            const new_params = @typeInfo(NewFn).@"fn".params;
            var types: [new_params.len]type = undefined;
            for (0..new_params.len) |i| {
                types[i] = new_params[i].type.?;
            }
            return std.meta.Tuple(&types);
        }

        /// __del__ - deallocate object
        pub fn py_dealloc(self_obj: ?*py.PyObject) callconv(.c) void {
            const obj = self_obj orelse return;
            const self: *PyWrapper = @ptrCast(@alignCast(obj));

            const obj_type = py.Py_TYPE(obj);

            if (has_weakref_support) {
                if (self.getWeakRefList()) |_| {
                    py.PyObject_ClearWeakRefs(obj);
                }
            }

            if (has_dict_support) {
                if (self.getDict()) |dict| {
                    py.Py_DecRef(dict);
                    self.setDict(null);
                }
            }

            // In ABI3 mode, PyTypeObject is opaque so we can't access tp_flags or tp_free
            // All types created via PyType_FromSpec are heap types
            if (comptime abi.abi3_enabled) {
                // Free the object
                py.PyObject_Del(self_obj);
                // Decref the type (heap types need this)
                if (obj_type) |t| {
                    py.Py_DecRef(@ptrCast(@alignCast(t)));
                }
            } else {
                const tp: ?*py.PyTypeObject = obj_type;
                const is_heaptype = if (tp) |t| (t.tp_flags & py.Py_TPFLAGS_HEAPTYPE) != 0 else false;

                if (obj_type) |t| {
                    if (t.tp_free) |free_fn| {
                        free_fn(self_obj);
                    } else {
                        py.PyObject_Del(self_obj);
                    }
                } else {
                    py.PyObject_Del(self_obj);
                }

                if (is_heaptype) {
                    if (tp) |t| {
                        py.Py_DecRef(@ptrCast(t));
                    }
                }
            }
        }

        // Expose whether this is a builtin subclass
        pub const is_builtin = is_builtin_subclass;

        // Reference to type object for other modules
        // Note: In ABI3 mode, this will panic - use Parent.getType() instead
        pub fn getTypeObject() *py.PyTypeObject {
            if (comptime abi.abi3_enabled) {
                @panic("getTypeObject not available in ABI3 mode - use Parent.getType() instead");
            } else {
                return type_object_ptr;
            }
        }
    };
}
