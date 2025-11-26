//! Type Conversion Module
//!
//! Provides conversion between Zig types and Python objects.
//! This is the core conversion engine used by function wrappers and class methods.

const std = @import("std");
const py = @import("python.zig");
const class_mod = @import("class.zig");
const PyObject = py.PyObject;

// Import all types
const complex_types = @import("types/complex.zig");
pub const Complex = complex_types.Complex;
pub const Complex32 = complex_types.Complex32;

const datetime_types = @import("types/datetime.zig");
pub const Date = datetime_types.Date;
pub const Time = datetime_types.Time;
pub const DateTime = datetime_types.DateTime;
pub const TimeDelta = datetime_types.TimeDelta;

const bytes_types = @import("types/bytes.zig");
pub const Bytes = bytes_types.Bytes;
pub const ByteArray = bytes_types.ByteArray;

const path_types = @import("types/path.zig");
pub const Path = path_types.Path;

const decimal_mod = @import("types/decimal.zig");
pub const Decimal = decimal_mod.Decimal;
pub const initDecimal = decimal_mod.initDecimal;
pub const PyDecimal_Check = decimal_mod.PyDecimal_Check;
pub const PyDecimal_FromString = decimal_mod.PyDecimal_FromString;
pub const PyDecimal_AsString = decimal_mod.PyDecimal_AsString;

const buffer_types = @import("types/buffer.zig");
pub const BufferView = buffer_types.BufferView;
pub const BufferViewMut = buffer_types.BufferViewMut;
pub const BufferInfo = buffer_types.BufferInfo;
const checkBufferFormat = buffer_types.checkBufferFormat;

/// Type conversion implementations - creates a converter aware of registered classes
pub fn Converter(comptime class_types: []const type) type {
    return struct {
        /// Convert Zig value to Python object
        pub fn toPy(comptime T: type, value: T) ?*PyObject {
            const info = @typeInfo(T);

            return switch (info) {
                .int => |int_info| {
                    // Handle 128-bit integers via string conversion
                    if (int_info.bits > 64) {
                        var buf: [48]u8 = undefined;
                        const str = std.fmt.bufPrintZ(&buf, "{d}", .{value}) catch return null;
                        return py.PyLong_FromString(str, null, 10);
                    }
                    if (int_info.signedness == .signed) {
                        return py.PyLong_FromLongLong(@intCast(value));
                    } else {
                        return py.PyLong_FromUnsignedLongLong(@intCast(value));
                    }
                },
                .comptime_int => py.PyLong_FromLongLong(@intCast(value)),
                .float => py.PyFloat_FromDouble(@floatCast(value)),
                .comptime_float => py.PyFloat_FromDouble(@floatCast(value)),
                .bool => py.Py_RETURN_BOOL(value),
                .pointer => |ptr| {
                    // Handle *PyObject directly - just return it as-is
                    if (ptr.child == PyObject) {
                        return value;
                    }
                    // String slice
                    if (ptr.size == .slice and ptr.child == u8) {
                        return py.PyUnicode_FromStringAndSize(value.ptr, @intCast(value.len));
                    }
                    // Null-terminated string (many-pointer)
                    if (ptr.size == .many and ptr.child == u8 and ptr.sentinel_ptr != null) {
                        return py.PyUnicode_FromString(value);
                    }
                    // String literal (*const [N:0]u8) - pointer to null-terminated array
                    if (ptr.size == .one) {
                        const child_info = @typeInfo(ptr.child);
                        if (child_info == .array) {
                            const arr = child_info.array;
                            if (arr.child == u8 and arr.sentinel_ptr != null) {
                                return py.PyUnicode_FromString(value);
                            }
                        }
                    }
                    // Generic slice -> Python list
                    if (ptr.size == .slice) {
                        const list = py.PyList_New(@intCast(value.len)) orelse return null;
                        for (value, 0..) |item, i| {
                            const py_item = toPy(ptr.child, item) orelse {
                                py.Py_DecRef(list);
                                return null;
                            };
                            // PyList_SetItem steals reference
                            if (py.PyList_SetItem(list, @intCast(i), py_item) < 0) {
                                py.Py_DecRef(list);
                                return null;
                            }
                        }
                        return list;
                    }
                    // Check if it's a pointer to a registered class - wrap it
                    inline for (class_types) |ClassType| {
                        if (ptr.child == ClassType) {
                            // TODO: Create a new Python object wrapping this pointer
                            // For now, return null - we'd need to copy the data
                            return null;
                        }
                    }
                    return null;
                },
                .optional => {
                    if (value) |v| {
                        return toPy(@TypeOf(v), v);
                    } else {
                        // If an exception is already set, return null (error indicator)
                        // Otherwise return None
                        if (py.PyErr_Occurred() != null) {
                            return null;
                        }
                        return py.Py_RETURN_NONE();
                    }
                },
                .error_union => {
                    if (value) |v| {
                        return toPy(@TypeOf(v), v);
                    } else |_| {
                        return null;
                    }
                },
                .void => py.Py_RETURN_NONE(),
                .@"struct" => |struct_info| {
                    // Handle Complex type - convert to Python complex
                    if (T == Complex) {
                        return py.PyComplex_FromDoubles(value.real, value.imag);
                    }

                    // Handle DateTime types
                    if (T == DateTime) {
                        return py.PyDateTime_FromDateAndTime(
                            @intCast(value.year),
                            @intCast(value.month),
                            @intCast(value.day),
                            @intCast(value.hour),
                            @intCast(value.minute),
                            @intCast(value.second),
                            @intCast(value.microsecond),
                        );
                    }

                    if (T == Date) {
                        return py.PyDate_FromDate(
                            @intCast(value.year),
                            @intCast(value.month),
                            @intCast(value.day),
                        );
                    }

                    if (T == Time) {
                        return py.PyTime_FromTime(
                            @intCast(value.hour),
                            @intCast(value.minute),
                            @intCast(value.second),
                            @intCast(value.microsecond),
                        );
                    }

                    if (T == TimeDelta) {
                        return py.PyDelta_FromDSU(
                            value.days,
                            value.seconds,
                            value.microseconds,
                        );
                    }

                    // Handle Bytes type
                    if (T == Bytes) {
                        return py.PyBytes_FromStringAndSize(value.data.ptr, @intCast(value.data.len));
                    }

                    // Handle Path type
                    if (T == Path) {
                        return py.PyPath_FromString(value.path);
                    }

                    // Handle Decimal type
                    if (T == Decimal) {
                        return PyDecimal_FromString(value.value);
                    }

                    // Handle tuple returns - convert struct to Python tuple
                    if (struct_info.is_tuple) {
                        const fields = struct_info.fields;
                        const tuple = py.PyTuple_New(@intCast(fields.len)) orelse return null;
                        inline for (fields, 0..) |field, i| {
                            const py_val = toPy(field.type, @field(value, field.name)) orelse {
                                py.Py_DecRef(tuple);
                                return null;
                            };
                            // PyTuple_SetItem steals reference, so don't decref py_val
                            if (py.PyTuple_SetItem(tuple, @intCast(i), py_val) < 0) {
                                py.Py_DecRef(tuple);
                                return null;
                            }
                        }
                        return tuple;
                    }

                    // Check if this is a Dict type - convert entries to Python dict
                    if (@hasDecl(T, "KeyType") and @hasDecl(T, "ValueType") and @hasDecl(T, "Entry")) {
                        const dict = py.PyDict_New() orelse return null;
                        for (value.entries) |entry| {
                            const py_key = toPy(T.KeyType, entry.key) orelse {
                                py.Py_DecRef(dict);
                                return null;
                            };
                            const py_val = toPy(T.ValueType, entry.value) orelse {
                                py.Py_DecRef(py_key);
                                py.Py_DecRef(dict);
                                return null;
                            };
                            if (py.PyDict_SetItem(dict, py_key, py_val) < 0) {
                                py.Py_DecRef(py_key);
                                py.Py_DecRef(py_val);
                                py.Py_DecRef(dict);
                                return null;
                            }
                            py.Py_DecRef(py_key);
                            py.Py_DecRef(py_val);
                        }
                        return dict;
                    }

                    // Check if this is a Set or FrozenSet type - convert items to Python set
                    if (@hasDecl(T, "ElementType") and @hasField(T, "items") and !@hasDecl(T, "KeyType")) {
                        const is_frozen = @hasDecl(T, "is_frozen") and T.is_frozen;
                        const set_obj = if (is_frozen)
                            py.PyFrozenSet_New(null)
                        else
                            py.PySet_New(null);
                        const set = set_obj orelse return null;

                        for (value.items) |item| {
                            const py_item = toPy(T.ElementType, item) orelse {
                                py.Py_DecRef(set);
                                return null;
                            };
                            if (py.PySet_Add(set, py_item) < 0) {
                                py.Py_DecRef(py_item);
                                py.Py_DecRef(set);
                                return null;
                            }
                            py.Py_DecRef(py_item);
                        }
                        return set;
                    }

                    // Check if this is a registered class type - create a new Python object
                    inline for (class_types) |ClassType| {
                        if (T == ClassType) {
                            const Wrapper = class_mod.getWrapper(ClassType);
                            // Allocate a new Python object
                            const py_obj = py.PyObject_New(Wrapper.PyWrapper, &Wrapper.type_object) orelse return null;
                            // Copy the data
                            py_obj.getData().* = value;
                            return @ptrCast(py_obj);
                        }
                    }

                    return null;
                },
                else => null,
            };
        }

        /// Convert Python object to Zig value with class type awareness
        pub fn fromPy(comptime T: type, obj: *PyObject) !T {
            const info = @typeInfo(T);

            // Check if T is a pointer to a registered class type
            if (info == .pointer) {
                const ptr_info = info.pointer;
                const Child = ptr_info.child;

                // Handle *PyObject directly - just return the object as-is
                if (Child == PyObject) {
                    return obj;
                }

                // Check each registered class type
                inline for (class_types) |ClassType| {
                    if (Child == ClassType) {
                        const Wrapper = class_mod.getWrapper(ClassType);
                        if (ptr_info.is_const) {
                            return Wrapper.unwrapConst(obj) orelse return error.TypeError;
                        } else {
                            return Wrapper.unwrap(obj) orelse return error.TypeError;
                        }
                    }
                }

                // Handle string slices
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    if (!py.PyUnicode_Check(obj)) {
                        return error.TypeError;
                    }
                    var size: py.Py_ssize_t = 0;
                    const ptr_data = py.PyUnicode_AsUTF8AndSize(obj, &size) orelse return error.ConversionError;
                    return ptr_data[0..@intCast(size)];
                }

                return error.TypeError;
            }

            // Check if T is Complex type
            if (T == Complex) {
                if (py.PyComplex_Check(obj)) {
                    return Complex{
                        .real = py.PyComplex_RealAsDouble(obj),
                        .imag = py.PyComplex_ImagAsDouble(obj),
                    };
                } else if (py.PyFloat_Check(obj)) {
                    return Complex{
                        .real = py.PyFloat_AsDouble(obj),
                        .imag = 0.0,
                    };
                } else if (py.PyLong_Check(obj)) {
                    return Complex{
                        .real = py.PyLong_AsDouble(obj),
                        .imag = 0.0,
                    };
                }
                return error.TypeError;
            }

            // Check if T is DateTime type
            if (T == DateTime) {
                if (py.PyDateTime_Check(obj)) {
                    return DateTime{
                        .year = @intCast(py.PyDateTime_GET_YEAR(obj)),
                        .month = @intCast(py.PyDateTime_GET_MONTH(obj)),
                        .day = @intCast(py.PyDateTime_GET_DAY(obj)),
                        .hour = @intCast(py.PyDateTime_DATE_GET_HOUR(obj)),
                        .minute = @intCast(py.PyDateTime_DATE_GET_MINUTE(obj)),
                        .second = @intCast(py.PyDateTime_DATE_GET_SECOND(obj)),
                        .microsecond = @intCast(py.PyDateTime_DATE_GET_MICROSECOND(obj)),
                    };
                }
                return error.TypeError;
            }

            // Check if T is Date type
            if (T == Date) {
                if (py.PyDate_Check(obj)) {
                    return Date{
                        .year = @intCast(py.PyDateTime_GET_YEAR(obj)),
                        .month = @intCast(py.PyDateTime_GET_MONTH(obj)),
                        .day = @intCast(py.PyDateTime_GET_DAY(obj)),
                    };
                }
                return error.TypeError;
            }

            // Check if T is Time type
            if (T == Time) {
                if (py.PyTime_Check(obj)) {
                    return Time{
                        .hour = @intCast(py.PyDateTime_TIME_GET_HOUR(obj)),
                        .minute = @intCast(py.PyDateTime_TIME_GET_MINUTE(obj)),
                        .second = @intCast(py.PyDateTime_TIME_GET_SECOND(obj)),
                        .microsecond = @intCast(py.PyDateTime_TIME_GET_MICROSECOND(obj)),
                    };
                }
                return error.TypeError;
            }

            // Check if T is TimeDelta type
            if (T == TimeDelta) {
                if (py.PyDelta_Check(obj)) {
                    return TimeDelta{
                        .days = py.PyDateTime_DELTA_GET_DAYS(obj),
                        .seconds = py.PyDateTime_DELTA_GET_SECONDS(obj),
                        .microseconds = py.PyDateTime_DELTA_GET_MICROSECONDS(obj),
                    };
                }
                return error.TypeError;
            }

            // Check if T is Bytes type
            if (T == Bytes) {
                if (py.PyBytes_Check(obj)) {
                    const size = py.PyBytes_Size(obj);
                    const ptr = py.PyBytes_AsString(obj) orelse return error.ConversionError;
                    return Bytes{ .data = ptr[0..@intCast(size)] };
                } else if (py.PyByteArray_Check(obj)) {
                    const size = py.PyByteArray_Size(obj);
                    const ptr = py.PyByteArray_AsString(obj) orelse return error.ConversionError;
                    return Bytes{ .data = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is ByteArray type
            if (T == ByteArray) {
                if (py.PyByteArray_Check(obj)) {
                    const size = py.PyByteArray_Size(obj);
                    const ptr = py.PyByteArray_AsString(obj) orelse return error.ConversionError;
                    return ByteArray{ .data = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is Decimal type
            if (T == Decimal) {
                if (PyDecimal_Check(obj)) {
                    const str_val = PyDecimal_AsString(obj) orelse return error.ConversionError;
                    return Decimal{ .value = str_val };
                } else if (py.PyLong_Check(obj) or py.PyFloat_Check(obj)) {
                    // Also accept int/float - convert via str()
                    const str_obj = py.PyObject_Str(obj) orelse return error.ConversionError;
                    defer py.Py_DecRef(str_obj);
                    var size: py.Py_ssize_t = 0;
                    const ptr = py.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return error.ConversionError;
                    return Decimal{ .value = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is Path type
            if (T == Path) {
                if (py.PyPath_Check(obj)) {
                    const path_str = py.PyPath_AsString(obj) orelse return error.ConversionError;
                    return Path{ .path = path_str };
                } else if (py.PyUnicode_Check(obj)) {
                    // Also accept plain strings as paths
                    var size: py.Py_ssize_t = 0;
                    const ptr = py.PyUnicode_AsUTF8AndSize(obj, &size) orelse return error.ConversionError;
                    return Path{ .path = ptr[0..@intCast(size)] };
                }
                return error.TypeError;
            }

            // Check if T is a DictView type
            if (info == .@"struct" and @hasDecl(T, "py_dict") == false and @hasField(T, "py_dict")) {
                if (!py.PyDict_Check(obj)) {
                    return error.TypeError;
                }
                return T{ .py_dict = obj };
            }

            // Check if T is a ListView type
            if (info == .@"struct" and @hasDecl(T, "py_list") == false and @hasField(T, "py_list")) {
                if (!py.PyList_Check(obj)) {
                    return error.TypeError;
                }
                return T{ .py_list = obj };
            }

            // Check if T is a SetView type
            if (info == .@"struct" and @hasDecl(T, "py_set") == false and @hasField(T, "py_set")) {
                if (!py.PyAnySet_Check(obj)) {
                    return error.TypeError;
                }
                return T{ .py_set = obj };
            }

            // Check if T is an IteratorView type
            if (info == .@"struct" and @hasDecl(T, "py_iter") == false and @hasField(T, "py_iter")) {
                // Get an iterator from the object (works for any iterable)
                const iter = py.PyObject_GetIter(obj) orelse {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Object is not iterable");
                    return error.TypeError;
                };
                return T{ .py_iter = iter };
            }

            // Check if T is a BufferView or BufferViewMut type
            if (info == .@"struct" and @hasDecl(T, "is_buffer_view") and T.is_buffer_view) {
                const ElementType = T.ElementType;
                const is_mutable = T.is_mutable;

                // Check if object supports buffer protocol
                if (!py.PyObject_CheckBuffer(obj)) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Object does not support buffer protocol");
                    return error.TypeError;
                }

                var buffer: py.Py_buffer = std.mem.zeroes(py.Py_buffer);
                const flags: c_int = if (is_mutable)
                    py.PyBUF_WRITABLE | py.PyBUF_FORMAT | py.PyBUF_ND | py.PyBUF_STRIDES | py.PyBUF_ANY_CONTIGUOUS
                else
                    py.PyBUF_FORMAT | py.PyBUF_ND | py.PyBUF_STRIDES | py.PyBUF_ANY_CONTIGUOUS;

                if (py.PyObject_GetBuffer(obj, &buffer, flags) < 0) {
                    return error.TypeError;
                }

                // Validate the format matches the expected element type
                if (buffer.format) |fmt| {
                    if (!checkBufferFormat(ElementType, fmt)) {
                        py.PyBuffer_Release(&buffer);
                        py.PyErr_SetString(py.PyExc_TypeError(), "Buffer format does not match expected type");
                        return error.TypeError;
                    }
                }

                // Validate item size
                if (buffer.itemsize != @sizeOf(ElementType)) {
                    py.PyBuffer_Release(&buffer);
                    py.PyErr_SetString(py.PyExc_TypeError(), "Buffer item size mismatch");
                    return error.TypeError;
                }

                // Calculate total number of elements
                var num_elements: usize = 1;
                const ndim: usize = @intCast(buffer.ndim);
                if (buffer.shape) |shape| {
                    for (0..ndim) |i| {
                        num_elements *= @intCast(shape[i]);
                    }
                } else {
                    num_elements = @intCast(@divExact(buffer.len, buffer.itemsize));
                }

                // Create the slice from the buffer
                const ptr: [*]ElementType = @ptrCast(@alignCast(buffer.buf.?));

                if (is_mutable) {
                    return T{
                        .data = ptr[0..num_elements],
                        .ndim = ndim,
                        .shape = if (buffer.shape) |s| s[0..ndim] else &[_]py.Py_ssize_t{@intCast(num_elements)},
                        .strides = if (buffer.strides) |s| s[0..ndim] else null,
                        ._py_obj = obj,
                        ._buffer = buffer,
                    };
                } else {
                    return T{
                        .data = ptr[0..num_elements],
                        .ndim = ndim,
                        .shape = if (buffer.shape) |s| s[0..ndim] else &[_]py.Py_ssize_t{@intCast(num_elements)},
                        .strides = if (buffer.strides) |s| s[0..ndim] else null,
                        ._py_obj = obj,
                        ._buffer = buffer,
                    };
                }
            }

            return switch (info) {
                .int => |int_info| {
                    if (!py.PyLong_Check(obj)) {
                        return error.TypeError;
                    }
                    // Handle 128-bit integers via string conversion
                    if (int_info.bits > 64) {
                        const str_obj = py.PyObject_Str(obj) orelse return error.ConversionError;
                        defer py.Py_DecRef(str_obj);
                        var size: py.Py_ssize_t = 0;
                        const ptr = py.PyUnicode_AsUTF8AndSize(str_obj, &size) orelse return error.ConversionError;
                        const str = ptr[0..@intCast(size)];
                        if (int_info.signedness == .signed) {
                            return std.fmt.parseInt(T, str, 10) catch return error.ConversionError;
                        } else {
                            return std.fmt.parseUnsigned(T, str, 10) catch return error.ConversionError;
                        }
                    }
                    if (int_info.signedness == .signed) {
                        const val = py.PyLong_AsLongLong(obj);
                        if (py.PyErr_Occurred() != null) return error.ConversionError;
                        return @intCast(val);
                    } else {
                        const val = py.PyLong_AsUnsignedLongLong(obj);
                        if (py.PyErr_Occurred() != null) return error.ConversionError;
                        return @intCast(val);
                    }
                },
                .float => {
                    if (py.PyFloat_Check(obj)) {
                        return @floatCast(py.PyFloat_AsDouble(obj));
                    } else if (py.PyLong_Check(obj)) {
                        return @floatCast(py.PyLong_AsDouble(obj));
                    }
                    return error.TypeError;
                },
                .bool => {
                    return py.PyObject_IsTrue(obj) == 1;
                },
                .optional => |opt| {
                    if (py.PyNone_Check(obj)) {
                        return null;
                    }
                    return try fromPy(opt.child, obj);
                },
                .array => |arr| {
                    // Fixed-size array from Python list
                    if (!py.PyList_Check(obj)) {
                        return error.TypeError;
                    }
                    const list_len = py.PyList_Size(obj);
                    if (list_len != arr.len) {
                        return error.WrongArgumentCount;
                    }
                    var result: T = undefined;
                    for (0..arr.len) |i| {
                        const item = py.PyList_GetItem(obj, @intCast(i)) orelse return error.InvalidArgument;
                        result[i] = try fromPy(arr.child, item);
                    }
                    return result;
                },
                else => error.TypeError,
            };
        }
    };
}

/// Basic conversions (no class awareness) - for backwards compatibility
pub const Conversions = Converter(&[_]type{});
