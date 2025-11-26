//! Number protocol for class generation
//!
//! Implements __add__, __sub__, __mul__, __neg__, __truediv__, etc.

const std = @import("std");
const py = @import("../python.zig");
const conversion = @import("../conversion.zig");

fn getSelfAwareConverter(comptime T: type) type {
    return conversion.Converter(&[_]type{T});
}

/// Build number protocol for a given type
pub fn NumberProtocol(comptime T: type, comptime Parent: type) type {
    const Conv = getSelfAwareConverter(T);

    return struct {
        pub fn hasNumberMethods() bool {
            return @hasDecl(T, "__add__") or @hasDecl(T, "__sub__") or
                @hasDecl(T, "__mul__") or @hasDecl(T, "__neg__") or
                @hasDecl(T, "__bool__") or @hasDecl(T, "__truediv__") or
                @hasDecl(T, "__floordiv__") or @hasDecl(T, "__mod__") or
                @hasDecl(T, "__divmod__") or
                @hasDecl(T, "__pow__") or @hasDecl(T, "__pos__") or
                @hasDecl(T, "__abs__") or @hasDecl(T, "__invert__") or
                @hasDecl(T, "__lshift__") or @hasDecl(T, "__rshift__") or
                @hasDecl(T, "__and__") or @hasDecl(T, "__or__") or
                @hasDecl(T, "__xor__") or @hasDecl(T, "__matmul__") or
                @hasDecl(T, "__int__") or @hasDecl(T, "__float__") or
                @hasDecl(T, "__complex__") or @hasDecl(T, "__index__") or
                @hasDecl(T, "__iadd__") or @hasDecl(T, "__isub__") or
                @hasDecl(T, "__imul__") or @hasDecl(T, "__itruediv__") or
                @hasDecl(T, "__ifloordiv__") or @hasDecl(T, "__imod__") or
                @hasDecl(T, "__ipow__") or @hasDecl(T, "__ilshift__") or
                @hasDecl(T, "__irshift__") or @hasDecl(T, "__iand__") or
                @hasDecl(T, "__ior__") or @hasDecl(T, "__ixor__") or
                @hasDecl(T, "__imatmul__") or
                @hasDecl(T, "__radd__") or @hasDecl(T, "__rsub__") or
                @hasDecl(T, "__rmul__") or @hasDecl(T, "__rtruediv__") or
                @hasDecl(T, "__rfloordiv__") or @hasDecl(T, "__rmod__") or
                @hasDecl(T, "__rdivmod__") or
                @hasDecl(T, "__rpow__") or @hasDecl(T, "__rlshift__") or
                @hasDecl(T, "__rrshift__") or @hasDecl(T, "__rand__") or
                @hasDecl(T, "__ror__") or @hasDecl(T, "__rxor__") or
                @hasDecl(T, "__rmatmul__");
        }

        pub var number_methods: py.c.PyNumberMethods = makeNumberMethods();

        fn makeNumberMethods() py.c.PyNumberMethods {
            var nm: py.c.PyNumberMethods = std.mem.zeroes(py.c.PyNumberMethods);

            if (@hasDecl(T, "__add__")) nm.nb_add = @ptrCast(&py_nb_add);
            if (@hasDecl(T, "__sub__")) nm.nb_subtract = @ptrCast(&py_nb_sub);
            if (@hasDecl(T, "__mul__")) nm.nb_multiply = @ptrCast(&py_nb_mul);
            if (@hasDecl(T, "__neg__")) nm.nb_negative = @ptrCast(&py_nb_neg);
            if (@hasDecl(T, "__truediv__")) nm.nb_true_divide = @ptrCast(&py_nb_truediv);
            if (@hasDecl(T, "__floordiv__")) nm.nb_floor_divide = @ptrCast(&py_nb_floordiv);
            if (@hasDecl(T, "__mod__")) nm.nb_remainder = @ptrCast(&py_nb_mod);
            if (@hasDecl(T, "__divmod__")) nm.nb_divmod = @ptrCast(&py_nb_divmod);
            if (@hasDecl(T, "__bool__")) nm.nb_bool = @ptrCast(&py_nb_bool);
            if (@hasDecl(T, "__pow__")) nm.nb_power = @ptrCast(&py_nb_pow);
            if (@hasDecl(T, "__pos__")) nm.nb_positive = @ptrCast(&py_nb_pos);
            if (@hasDecl(T, "__abs__")) nm.nb_absolute = @ptrCast(&py_nb_abs);
            if (@hasDecl(T, "__invert__")) nm.nb_invert = @ptrCast(&py_nb_invert);
            if (@hasDecl(T, "__lshift__")) nm.nb_lshift = @ptrCast(&py_nb_lshift);
            if (@hasDecl(T, "__rshift__")) nm.nb_rshift = @ptrCast(&py_nb_rshift);
            if (@hasDecl(T, "__and__")) nm.nb_and = @ptrCast(&py_nb_and);
            if (@hasDecl(T, "__or__")) nm.nb_or = @ptrCast(&py_nb_or);
            if (@hasDecl(T, "__xor__")) nm.nb_xor = @ptrCast(&py_nb_xor);
            if (@hasDecl(T, "__matmul__")) nm.nb_matrix_multiply = @ptrCast(&py_nb_matmul);
            if (@hasDecl(T, "__int__")) nm.nb_int = @ptrCast(&py_nb_int);
            if (@hasDecl(T, "__float__")) nm.nb_float = @ptrCast(&py_nb_float);
            if (@hasDecl(T, "__index__")) nm.nb_index = @ptrCast(&py_nb_index);
            // In-place operators
            if (@hasDecl(T, "__iadd__")) nm.nb_inplace_add = @ptrCast(&py_nb_iadd);
            if (@hasDecl(T, "__isub__")) nm.nb_inplace_subtract = @ptrCast(&py_nb_isub);
            if (@hasDecl(T, "__imul__")) nm.nb_inplace_multiply = @ptrCast(&py_nb_imul);
            if (@hasDecl(T, "__itruediv__")) nm.nb_inplace_true_divide = @ptrCast(&py_nb_itruediv);
            if (@hasDecl(T, "__ifloordiv__")) nm.nb_inplace_floor_divide = @ptrCast(&py_nb_ifloordiv);
            if (@hasDecl(T, "__imod__")) nm.nb_inplace_remainder = @ptrCast(&py_nb_imod);
            if (@hasDecl(T, "__ipow__")) nm.nb_inplace_power = @ptrCast(&py_nb_ipow);
            if (@hasDecl(T, "__ilshift__")) nm.nb_inplace_lshift = @ptrCast(&py_nb_ilshift);
            if (@hasDecl(T, "__irshift__")) nm.nb_inplace_rshift = @ptrCast(&py_nb_irshift);
            if (@hasDecl(T, "__iand__")) nm.nb_inplace_and = @ptrCast(&py_nb_iand);
            if (@hasDecl(T, "__ior__")) nm.nb_inplace_or = @ptrCast(&py_nb_ior);
            if (@hasDecl(T, "__ixor__")) nm.nb_inplace_xor = @ptrCast(&py_nb_ixor);
            if (@hasDecl(T, "__imatmul__")) nm.nb_inplace_matrix_multiply = @ptrCast(&py_nb_imatmul);

            return nm;
        }

        fn py_nb_add(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__add__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__add__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__radd__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__radd__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            if (self_is_T and !other_is_T) {
                if (@hasDecl(T, "__add__")) {
                    const AddFn = @TypeOf(T.__add__);
                    const add_params = @typeInfo(AddFn).@"fn".params;
                    if (add_params.len >= 2) {
                        const OtherType = add_params[1].type.?;
                        if (OtherType == ?*py.PyObject or OtherType == *py.PyObject) {
                            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                            const result = T.__add__(self.getDataConst(), other_obj.?);
                            return Conv.toPy(@TypeOf(result), result);
                        }
                    }
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_sub(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__sub__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__sub__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rsub__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rsub__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_mul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__mul__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__mul__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rmul__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rmul__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_neg(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__neg__(self.getDataConst());
            return Conv.toPy(T, result);
        }

        fn py_nb_truediv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__truediv__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const TrueDivFn = @TypeOf(T.__truediv__);
                    const RetType = @typeInfo(TrueDivFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__truediv__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        return Conv.toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__truediv__(self.getDataConst(), other.getDataConst());
                        return Conv.toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rtruediv__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rtruediv__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_floordiv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__floordiv__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const FloorDivFn = @TypeOf(T.__floordiv__);
                    const RetType = @typeInfo(FloorDivFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__floordiv__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        return Conv.toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__floordiv__(self.getDataConst(), other.getDataConst());
                        return Conv.toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rfloordiv__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rfloordiv__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_mod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__mod__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const ModFn = @TypeOf(T.__mod__);
                    const RetType = @typeInfo(ModFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__mod__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        return Conv.toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__mod__(self.getDataConst(), other.getDataConst());
                        return Conv.toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rmod__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rmod__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_divmod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__divmod__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const DivmodFn = @TypeOf(T.__divmod__);
                    const RetType = @typeInfo(DivmodFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__divmod__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        return Conv.toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__divmod__(self.getDataConst(), other.getDataConst());
                        return Conv.toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rdivmod__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rdivmod__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_bool(self_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const result = T.__bool__(self.getDataConst());
            return if (result) 1 else 0;
        }

        fn py_nb_pow(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, mod_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = mod_obj;
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__pow__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const PowFn = @TypeOf(T.__pow__);
                    const RetType = @typeInfo(PowFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__pow__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ValueError(), msg.ptr);
                            return null;
                        };
                        return Conv.toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__pow__(self.getDataConst(), other.getDataConst());
                        return Conv.toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rpow__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rpow__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_pos(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__pos__(self.getDataConst());
            return Conv.toPy(T, result);
        }

        fn py_nb_abs(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__abs__(self.getDataConst());
            return Conv.toPy(T, result);
        }

        fn py_nb_invert(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__invert__(self.getDataConst());
            return Conv.toPy(T, result);
        }

        fn py_nb_lshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__lshift__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__lshift__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rlshift__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rlshift__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_rshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__rshift__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rshift__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rrshift__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rrshift__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_and(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__and__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__and__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rand__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rand__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_or(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__or__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__or__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__ror__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__ror__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_xor(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__xor__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__xor__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rxor__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rxor__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_matmul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, Parent.getTypeObjectPtr());
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr());

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__matmul__")) {
                    const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const MatmulFn = @TypeOf(T.__matmul__);
                    const RetType = @typeInfo(MatmulFn).@"fn".return_type.?;
                    const result = T.__matmul__(self.getDataConst(), other.getDataConst());
                    return Conv.toPy(RetType, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rmatmul__")) {
                    const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rmatmul__(other.getDataConst(), self_obj.?);
                    return Conv.toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_int(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__int__(self.getDataConst());
            return conversion.Conversions.toPy(@TypeOf(result), result);
        }

        fn py_nb_float(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__float__(self.getDataConst());
            return conversion.Conversions.toPy(@TypeOf(result), result);
        }

        fn py_nb_index(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__index__(self.getDataConst());
            return conversion.Conversions.toPy(@TypeOf(result), result);
        }

        // In-place operators
        fn py_nb_iadd(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__iadd__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_isub(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__isub__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_imul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__imul__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_itruediv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__itruediv__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ifloordiv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__ifloordiv__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_imod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__imod__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ipow(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, mod_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = mod_obj;
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__ipow__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ilshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__ilshift__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_irshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__irshift__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_iand(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__iand__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ior(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__ior__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ixor(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__ixor__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_imatmul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }
            T.__imatmul__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }
    };
}
