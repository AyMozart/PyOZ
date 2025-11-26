//! Method wrapper generation for class generation
//!
//! Generates Python method wrappers for instance methods, static methods, and class methods

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

fn getConversions() type {
    return conversion.Conversions;
}

fn getSelfAwareConverter(comptime T: type) type {
    return conversion.Converter(&[_]type{T});
}

/// Build method wrappers for a given type
pub fn MethodBuilder(comptime T: type, comptime PyWrapper: type) type {
    const struct_info = @typeInfo(T).@"struct";
    const decls = struct_info.decls;

    return struct {
        const Self = @This();

        // ====================================================================
        // Method counting and detection
        // ====================================================================

        pub fn countMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isInstanceMethod(decl.name)) count += 1;
            }
            return count;
        }

        pub fn countStaticMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isStaticMethod(decl.name)) count += 1;
            }
            return count;
        }

        pub fn countClassMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isClassMethod(decl.name)) count += 1;
            }
            return count;
        }

        pub fn totalMethodCount() usize {
            return countMethods() + countStaticMethods() + countClassMethods();
        }

        fn isInstanceMethod(comptime decl_name: []const u8) bool {
            // Check if this is a public function that takes self
            if (!@hasDecl(T, decl_name)) return false;
            const decl = @field(T, decl_name);
            const DeclType = @TypeOf(decl);
            const decl_info = @typeInfo(DeclType);

            if (decl_info != .@"fn") return false;

            const fn_info = decl_info.@"fn";
            if (fn_info.params.len == 0) return false;

            // Check if first param is self (*T, *const T, or T)
            const FirstParam = fn_info.params[0].type orelse return false;
            const first_info = @typeInfo(FirstParam);

            if (first_info == .pointer) {
                const child = first_info.pointer.child;
                if (child == T) return true;
            }
            if (FirstParam == T) return true;

            return false;
        }

        fn isStaticMethod(comptime decl_name: []const u8) bool {
            // Check if this is a public function that does NOT take self or cls
            if (!@hasDecl(T, decl_name)) return false;

            // Exclude class methods
            if (isClassMethod(decl_name)) return false;

            const decl = @field(T, decl_name);
            const DeclType = @TypeOf(decl);
            const decl_info = @typeInfo(DeclType);

            if (decl_info != .@"fn") return false;

            const fn_info = decl_info.@"fn";

            // No parameters - static method
            if (fn_info.params.len == 0) return true;

            // Has parameters but first is not self - static method
            const FirstParam = fn_info.params[0].type orelse return true;
            const first_info = @typeInfo(FirstParam);

            if (first_info == .pointer) {
                const child = first_info.pointer.child;
                if (child == T) return false; // Instance method
            }
            if (FirstParam == T) return false; // Instance method

            return true; // Static method
        }

        fn isClassMethod(comptime decl_name: []const u8) bool {
            // Class methods have `comptime cls: type` as first parameter
            if (!@hasDecl(T, decl_name)) return false;
            const decl = @field(T, decl_name);
            const DeclType = @TypeOf(decl);
            const decl_info = @typeInfo(DeclType);

            if (decl_info != .@"fn") return false;

            const fn_info = decl_info.@"fn";
            if (fn_info.params.len == 0) return false;

            // Check if first param is `type` (comptime cls: type)
            const FirstParam = fn_info.params[0].type orelse return false;
            return FirstParam == type;
        }

        // ====================================================================
        // Docstring helpers
        // ====================================================================

        /// Get method docstring from method_name__doc__ declaration if it exists
        pub fn getMethodDoc(comptime method_name: []const u8) ?[*:0]const u8 {
            const doc_name = method_name ++ "__doc__";
            if (@hasDecl(T, doc_name)) {
                const DocType = @TypeOf(@field(T, doc_name));
                if (DocType != [*:0]const u8) {
                    @compileError(doc_name ++ " must be declared as [*:0]const u8, e.g.: pub const " ++ doc_name ++ ": [*:0]const u8 = \"...\";");
                }
                return @field(T, doc_name);
            }
            return null;
        }

        // ====================================================================
        // Method array generation
        // ====================================================================

        const total_count = totalMethodCount();

        pub var methods: [total_count + 1]py.PyMethodDef = blk: {
            var m: [total_count + 1]py.PyMethodDef = undefined;
            var idx: usize = 0;

            // Add instance methods
            for (decls) |decl| {
                if (isInstanceMethod(decl.name)) {
                    m[idx] = .{
                        .ml_name = @ptrCast(decl.name.ptr),
                        .ml_meth = @ptrCast(generateMethodWrapper(decl.name)),
                        .ml_flags = py.METH_VARARGS,
                        .ml_doc = getMethodDoc(decl.name),
                    };
                    idx += 1;
                }
            }

            // Add static methods
            for (decls) |decl| {
                if (isStaticMethod(decl.name)) {
                    m[idx] = .{
                        .ml_name = @ptrCast(decl.name.ptr),
                        .ml_meth = @ptrCast(generateStaticMethodWrapper(decl.name)),
                        .ml_flags = py.METH_VARARGS | py.METH_STATIC,
                        .ml_doc = getMethodDoc(decl.name),
                    };
                    idx += 1;
                }
            }

            // Add class methods
            for (decls) |decl| {
                if (isClassMethod(decl.name)) {
                    m[idx] = .{
                        .ml_name = @ptrCast(decl.name.ptr),
                        .ml_meth = @ptrCast(generateClassMethodWrapper(decl.name)),
                        .ml_flags = py.METH_VARARGS | py.METH_CLASS,
                        .ml_doc = getMethodDoc(decl.name),
                    };
                    idx += 1;
                }
            }

            // Sentinel
            m[total_count] = .{
                .ml_name = null,
                .ml_meth = null,
                .ml_flags = 0,
                .ml_doc = null,
            };

            break :blk m;
        };

        // ====================================================================
        // Instance method wrapper generation
        // ====================================================================

        fn generateMethodWrapper(comptime method_name: []const u8) *const fn (?*py.PyObject, ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const method = @field(T, method_name);
            const MethodType = @TypeOf(method);
            const fn_info = @typeInfo(MethodType).@"fn";
            const params = fn_info.params;
            const ReturnType = fn_info.return_type orelse void;

            return struct {
                fn wrapper(self_obj: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));

                    // Build argument tuple for the method call
                    const extra_args = parseMethodArgs(args) catch |err| {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                        return null;
                    };

                    // Call method with self pointer and extra args
                    const result = callMethod(self.getData(), extra_args);

                    // Handle return - pass self_obj for potential "return self" pattern
                    return handleReturn(result, self_obj.?, self.getData());
                }

                fn parseMethodArgs(py_args: ?*py.PyObject) !ExtraArgsTuple() {
                    var result: ExtraArgsTuple() = undefined;
                    const extra_param_count = params.len - 1;

                    if (extra_param_count == 0) {
                        return result;
                    }

                    const args_tuple = py_args orelse return error.MissingArguments;
                    const arg_count = py.PyTuple_Size(args_tuple);

                    if (arg_count != extra_param_count) {
                        return error.WrongArgumentCount;
                    }

                    comptime var i: usize = 0;
                    inline for (1..params.len) |param_idx| {
                        const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                        // Use self-aware converter so methods can take *const T parameters
                        result[i] = try getSelfAwareConverter(T).fromPy(params[param_idx].type.?, item);
                        i += 1;
                    }

                    return result;
                }

                fn ExtraArgsTuple() type {
                    if (params.len <= 1) return std.meta.Tuple(&[_]type{});
                    var types: [params.len - 1]type = undefined;
                    for (1..params.len) |i| {
                        types[i - 1] = params[i].type.?;
                    }
                    return std.meta.Tuple(&types);
                }

                fn callMethod(self_ptr: anytype, extra: ExtraArgsTuple()) ReturnType {
                    // Build the full args with self as first parameter
                    if (params.len == 1) {
                        return @call(.auto, method, .{self_ptr});
                    } else {
                        return @call(.auto, method, .{self_ptr} ++ extra);
                    }
                }

                fn handleReturn(result: ReturnType, self_obj: *py.PyObject, self_data: *T) ?*py.PyObject {
                    const rt_info = @typeInfo(ReturnType);
                    // Use self-aware converter so we can return instances of T
                    const Conv = getSelfAwareConverter(T);

                    // Check if return type is pointer to T (return self pattern)
                    if (rt_info == .pointer) {
                        const ptr_info = rt_info.pointer;
                        if (ptr_info.child == T) {
                            // Method returned *T or *const T - check if it's self
                            const result_ptr: *const T = if (ptr_info.is_const) result else result;
                            if (result_ptr == self_data) {
                                // Return self with incremented refcount
                                py.Py_IncRef(self_obj);
                                return self_obj;
                            }
                        }
                    }

                    if (rt_info == .error_union) {
                        if (result) |value| {
                            const ValueType = @TypeOf(value);
                            const val_info = @typeInfo(ValueType);
                            // Check for pointer to T in error union
                            if (val_info == .pointer and val_info.pointer.child == T) {
                                const result_ptr: *const T = if (val_info.pointer.is_const) value else value;
                                if (result_ptr == self_data) {
                                    py.Py_IncRef(self_obj);
                                    return self_obj;
                                }
                            }
                            return Conv.toPy(ValueType, value);
                        } else |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                            return null;
                        }
                    } else if (ReturnType == void) {
                        return py.Py_RETURN_NONE();
                    } else {
                        return Conv.toPy(ReturnType, result);
                    }
                }
            }.wrapper;
        }

        // ====================================================================
        // Static method wrapper generation
        // ====================================================================

        fn generateStaticMethodWrapper(comptime method_name: []const u8) *const fn (?*py.PyObject, ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const method = @field(T, method_name);
            const MethodType = @TypeOf(method);
            const fn_info = @typeInfo(MethodType).@"fn";
            const params = fn_info.params;
            const ReturnType = fn_info.return_type orelse void;
            // Use a converter that knows about type T so we can return T instances
            const Conv = getSelfAwareConverter(T);

            return struct {
                fn wrapper(self_obj: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
                    // Static methods ignore self (it's NULL or the type object)
                    _ = self_obj;

                    // Parse all arguments (no self to skip)
                    const zig_args = parseArgs(args) catch |err| {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                        return null;
                    };

                    // Call static method
                    const result = @call(.auto, method, zig_args);

                    // Handle return
                    return handleReturn(result);
                }

                fn parseArgs(py_args: ?*py.PyObject) !ArgsTuple() {
                    var result: ArgsTuple() = undefined;

                    if (params.len == 0) {
                        return result;
                    }

                    const args_tuple = py_args orelse return error.MissingArguments;
                    const arg_count = py.PyTuple_Size(args_tuple);

                    if (arg_count != params.len) {
                        return error.WrongArgumentCount;
                    }

                    comptime var i: usize = 0;
                    inline for (params) |param| {
                        const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                        result[i] = try Conv.fromPy(param.type.?, item);
                        i += 1;
                    }

                    return result;
                }

                fn ArgsTuple() type {
                    if (params.len == 0) return std.meta.Tuple(&[_]type{});
                    var types: [params.len]type = undefined;
                    for (params, 0..) |param, i| {
                        types[i] = param.type.?;
                    }
                    return std.meta.Tuple(&types);
                }

                fn handleReturn(result: ReturnType) ?*py.PyObject {
                    const rt_info = @typeInfo(ReturnType);
                    if (rt_info == .error_union) {
                        if (result) |value| {
                            return Conv.toPy(@TypeOf(value), value);
                        } else |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                            return null;
                        }
                    } else if (ReturnType == void) {
                        return py.Py_RETURN_NONE();
                    } else {
                        return Conv.toPy(ReturnType, result);
                    }
                }
            }.wrapper;
        }

        // ====================================================================
        // Class method wrapper generation
        // ====================================================================

        fn generateClassMethodWrapper(comptime method_name: []const u8) *const fn (?*py.PyObject, ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const method = @field(T, method_name);
            const MethodType = @TypeOf(method);
            const fn_info = @typeInfo(MethodType).@"fn";
            const params = fn_info.params;
            const ReturnType = fn_info.return_type orelse void;
            // Use a converter that knows about type T so we can return T instances
            const Conv = getSelfAwareConverter(T);

            return struct {
                fn wrapper(cls_obj: ?*py.PyObject, args: ?*py.PyObject) callconv(.c) ?*py.PyObject {
                    // For class methods, cls_obj is the type object
                    // We pass the Zig type T to the method
                    _ = cls_obj;

                    // Parse arguments (skip the first `type` parameter)
                    const zig_args = parseArgs(args) catch |err| {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                        return null;
                    };

                    // Call class method with T as first argument, then the rest
                    const result = @call(.auto, method, .{T} ++ zig_args);

                    // Handle return
                    return handleReturn(result);
                }

                fn parseArgs(py_args: ?*py.PyObject) !ArgsTuple() {
                    var result: ArgsTuple() = undefined;
                    const extra_param_count = params.len - 1; // Skip the `type` param

                    if (extra_param_count == 0) {
                        return result;
                    }

                    const args_tuple = py_args orelse return error.MissingArguments;
                    const arg_count = py.PyTuple_Size(args_tuple);

                    if (arg_count != extra_param_count) {
                        return error.WrongArgumentCount;
                    }

                    comptime var i: usize = 0;
                    inline for (1..params.len) |param_idx| {
                        const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                        result[i] = try Conv.fromPy(params[param_idx].type.?, item);
                        i += 1;
                    }

                    return result;
                }

                fn ArgsTuple() type {
                    if (params.len <= 1) return std.meta.Tuple(&[_]type{});
                    var types: [params.len - 1]type = undefined;
                    for (1..params.len) |i| {
                        types[i - 1] = params[i].type.?;
                    }
                    return std.meta.Tuple(&types);
                }

                fn handleReturn(result: ReturnType) ?*py.PyObject {
                    const rt_info = @typeInfo(ReturnType);
                    if (rt_info == .error_union) {
                        if (result) |value| {
                            return Conv.toPy(@TypeOf(value), value);
                        } else |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                            return null;
                        }
                    } else if (ReturnType == void) {
                        return py.Py_RETURN_NONE();
                    } else {
                        return Conv.toPy(ReturnType, result);
                    }
                }
            }.wrapper;
        }
    };
}
