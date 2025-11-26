//! Comparison protocol for class generation
//!
//! Implements __eq__, __ne__, __lt__, __le__, __gt__, __ge__

const py = @import("../python.zig");

// Rich comparison operation codes
pub const Py_LT: c_int = 0;
pub const Py_LE: c_int = 1;
pub const Py_EQ: c_int = 2;
pub const Py_NE: c_int = 3;
pub const Py_GT: c_int = 4;
pub const Py_GE: c_int = 5;

/// Build comparison protocol for a given type
pub fn ComparisonProtocol(comptime T: type, comptime Parent: type) type {
    return struct {
        pub fn hasComparisonMethods() bool {
            return @hasDecl(T, "__eq__") or @hasDecl(T, "__ne__") or
                @hasDecl(T, "__lt__") or @hasDecl(T, "__le__") or
                @hasDecl(T, "__gt__") or @hasDecl(T, "__ge__");
        }

        pub fn py_richcompare(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, op: c_int) callconv(.c) ?*py.PyObject {
            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *Parent.PyWrapper = @ptrCast(@alignCast(other_obj orelse {
                return py.Py_NotImplemented();
            }));

            if (!py.PyObject_TypeCheck(other_obj.?, Parent.getTypeObjectPtr())) {
                return py.Py_NotImplemented();
            }

            const result: bool = switch (op) {
                Py_EQ => if (@hasDecl(T, "__eq__")) T.__eq__(self.getDataConst(), other.getDataConst()) else return py.Py_NotImplemented(),
                Py_NE => if (@hasDecl(T, "__ne__"))
                    T.__ne__(self.getDataConst(), other.getDataConst())
                else if (@hasDecl(T, "__eq__"))
                    !T.__eq__(self.getDataConst(), other.getDataConst())
                else
                    return py.Py_NotImplemented(),
                Py_LT => if (@hasDecl(T, "__lt__")) T.__lt__(self.getDataConst(), other.getDataConst()) else return py.Py_NotImplemented(),
                Py_LE => if (@hasDecl(T, "__le__"))
                    T.__le__(self.getDataConst(), other.getDataConst())
                else if (@hasDecl(T, "__lt__") and @hasDecl(T, "__eq__"))
                    (T.__lt__(self.getDataConst(), other.getDataConst()) or T.__eq__(self.getDataConst(), other.getDataConst()))
                else
                    return py.Py_NotImplemented(),
                Py_GT => if (@hasDecl(T, "__gt__"))
                    T.__gt__(self.getDataConst(), other.getDataConst())
                else if (@hasDecl(T, "__lt__"))
                    T.__lt__(other.getDataConst(), self.getDataConst())
                else
                    return py.Py_NotImplemented(),
                Py_GE => if (@hasDecl(T, "__ge__"))
                    T.__ge__(self.getDataConst(), other.getDataConst())
                else if (@hasDecl(T, "__le__"))
                    T.__le__(other.getDataConst(), self.getDataConst())
                else if (@hasDecl(T, "__gt__") and @hasDecl(T, "__eq__"))
                    (T.__gt__(self.getDataConst(), other.getDataConst()) or T.__eq__(self.getDataConst(), other.getDataConst()))
                else
                    return py.Py_NotImplemented(),
                else => return py.Py_NotImplemented(),
            };

            return py.Py_RETURN_BOOL(result);
        }
    };
}
