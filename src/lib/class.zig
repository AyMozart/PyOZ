//! Class wrapper for PyOZ
//!
//! This module provides comptime generation of Python classes from Zig structs.
//! It automatically:
//! - Generates __init__ from struct fields
//! - Creates getters/setters for each field
//! - Wraps pub fn methods as Python methods

const std = @import("std");
const py = @import("python.zig");
const root = @import("root.zig");

// Forward declaration - we'll use basic conversions within class methods
// For instance methods, self is handled separately so basic conversions work
fn getConversions() type {
    return root.Conversions;
}

// Get a converter that knows about a specific class type T
fn getSelfAwareConverter(comptime T: type) type {
    return root.Converter(&[_]type{T});
}

/// Configuration for a class definition
pub const ClassDef = struct {
    name: [*:0]const u8,
    type_obj: *py.PyTypeObject,
};

/// Get the wrapper type for a Zig struct (for use in conversions)
pub fn getWrapper(comptime T: type) type {
    // We need a default name - use the type name
    return generateClass(@typeName(T), T);
}

/// Generate a Python class wrapper for a Zig struct
pub fn class(comptime name: [*:0]const u8, comptime T: type) ClassDef {
    const Generated = generateClass(name, T);
    return .{
        .name = name,
        .type_obj = &Generated.type_object,
    };
}

/// Generate all the wrapper code for a Zig struct
fn generateClass(comptime name: [*:0]const u8, comptime T: type) type {
    const struct_info = @typeInfo(T).@"struct";
    const fields = struct_info.fields;

    // Check if this is a "mixin" class that inherits from a Python built-in type
    // A mixin has __base__ defined and no instance fields (only methods/consts)
    const is_builtin_subclass = comptime blk: {
        if (!@hasDecl(T, "__base__")) break :blk false;
        // Check if there are any non-const fields
        for (fields) |field| {
            // If there's a runtime field, it's not a pure mixin
            _ = field;
            break :blk false;
        }
        break :blk true;
    };

    return struct {
        const Self = @This();

        // Check if this class wants __dict__ support for dynamic attributes
        const has_dict_support = blk: {
            if (@hasDecl(T, "__features__")) {
                const features = T.__features__;
                if (@hasField(@TypeOf(features), "dict")) {
                    break :blk features.dict;
                }
            }
            break :blk false;
        };

        // Check if this class wants weak reference support
        const has_weakref_support = blk: {
            if (@hasDecl(T, "__features__")) {
                const features = T.__features__;
                if (@hasField(@TypeOf(features), "weakref")) {
                    break :blk features.weakref;
                }
            }
            break :blk false;
        };

        // The Python object wrapper - contains PyObject header + Zig data
        // We store the Zig data as bytes to avoid extern struct compatibility issues
        // The layout must have ob_base at offset 0 for Python compatibility
        const DataSize = @sizeOf(T);
        const DataAlign = if (DataSize == 0) 1 else @alignOf(T);

        // Compute extra storage size for optional features (dict, weakref)
        const ptr_size = @sizeOf(?*py.PyObject);
        const dict_size = if (has_dict_support) ptr_size else 0;
        const weakref_size = if (has_weakref_support) ptr_size else 0;
        const extra_size = dict_size + weakref_size;

        // Offsets within _extra for each optional field
        const dict_offset: usize = 0;
        const weakref_offset: usize = dict_size; // weakref comes after dict (if present)

        // Extra storage alignment (pointers need proper alignment)
        const ExtraAlign = if (extra_size > 0) @alignOf(?*py.PyObject) else 1;

        // Single PyWrapper struct with computed extra storage
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

            /// Initialize extra fields to null
            pub fn initExtra(self: *@This()) void {
                if (has_dict_support) self.setDict(null);
                if (has_weakref_support) self.setWeakRefList(null);
            }
        };

        // ====================================================================
        // Members for __dict__ and __weakref__ support
        // ====================================================================

        // Compute the actual offset of dict within the struct
        const dict_struct_offset: py.Py_ssize_t = if (has_dict_support)
            @intCast(@offsetOf(PyWrapper, "_extra") + dict_offset)
        else
            0;

        // Compute the actual offset of weakreflist within the struct
        const weakref_struct_offset: py.Py_ssize_t = if (has_weakref_support)
            @intCast(@offsetOf(PyWrapper, "_extra") + weakref_offset)
        else
            0;

        // Count how many members we need (dict + weakref + sentinel)
        const member_count = (if (has_dict_support) @as(usize, 1) else 0) +
            (if (has_weakref_support) @as(usize, 1) else 0) + 1;

        // PyMemberDef array for exposing __dict__ and __weakref__ attributes
        var feature_members: [member_count]py.PyMemberDef = blk: {
            var members: [member_count]py.PyMemberDef = undefined;
            var idx: usize = 0;

            if (has_dict_support) {
                members[idx] = .{
                    .name = "__dict__",
                    .type = py.c.T_OBJECT_EX,
                    .offset = dict_struct_offset,
                    .flags = 0,
                    .doc = null,
                };
                idx += 1;
            }

            if (has_weakref_support) {
                members[idx] = .{
                    .name = "__weakref__",
                    .type = py.c.T_OBJECT_EX,
                    .offset = weakref_struct_offset,
                    .flags = py.c.READONLY,
                    .doc = null,
                };
                idx += 1;
            }

            // Sentinel
            members[idx] = .{
                .name = null,
                .type = 0,
                .offset = 0,
                .flags = 0,
                .doc = null,
            };

            break :blk members;
        };

        // ====================================================================
        // Type Object (static)
        // ====================================================================

        pub var type_object: py.PyTypeObject = makeTypeObject();

        fn makeTypeObject() py.PyTypeObject {
            var obj: py.PyTypeObject = std.mem.zeroes(py.PyTypeObject);

            // Basic setup
            obj.ob_base.ob_base.ob_refcnt = 1;
            obj.ob_base.ob_base.ob_type = null;
            obj.tp_name = name;
            // For builtin subclasses, let Python handle the size
            obj.tp_basicsize = if (is_builtin_subclass) 0 else @sizeOf(PyWrapper);
            obj.tp_itemsize = 0;
            obj.tp_flags = py.Py_TPFLAGS_DEFAULT | py.Py_TPFLAGS_BASETYPE |
                (if (hasGCSupport()) py.Py_TPFLAGS_HAVE_GC else 0);

            // Set tp_dictoffset for __dict__ support
            if (has_dict_support and !is_builtin_subclass) {
                obj.tp_dictoffset = dict_struct_offset;
            }

            // Set tp_weaklistoffset for weak reference support
            if (has_weakref_support and !is_builtin_subclass) {
                obj.tp_weaklistoffset = weakref_struct_offset;
            }

            // Inheritance - check for __base__ declaration
            // __base__ should be a function that returns ?*py.PyTypeObject
            if (@hasDecl(T, "__base__")) {
                obj.tp_base = T.__base__();
            }
            // Use __doc__ declaration if present, otherwise use class name
            obj.tp_doc = if (@hasDecl(T, "__doc__")) blk: {
                const DocType = @TypeOf(T.__doc__);
                if (DocType != [*:0]const u8) {
                    @compileError("__doc__ must be declared as [*:0]const u8, e.g.: pub const __doc__: [*:0]const u8 = \"...\";");
                }
                break :blk T.__doc__;
            } else name;

            // Slots - use @ptrCast to convert to C-compatible function pointers
            // For builtin subclasses, don't override tp_new/tp_init - let base handle them
            if (!is_builtin_subclass) {
                obj.tp_new = @ptrCast(&py_new);
                obj.tp_init = @ptrCast(&py_init);
                obj.tp_dealloc = @ptrCast(&py_dealloc);
            }
            obj.tp_methods = @ptrCast(&methods);
            obj.tp_getset = @ptrCast(&getset);

            // Set tp_members for __dict__ and __weakref__ support
            if ((has_dict_support or has_weakref_support) and !is_builtin_subclass) {
                obj.tp_members = @ptrCast(&feature_members);
            }

            // Magic methods - check if struct defines them
            // __repr__
            if (@hasDecl(T, "__repr__")) {
                obj.tp_repr = @ptrCast(&py_magic_repr);
            } else {
                obj.tp_repr = @ptrCast(&py_repr);
            }

            // __str__
            if (@hasDecl(T, "__str__")) {
                obj.tp_str = @ptrCast(&py_magic_str);
            }

            // __eq__ / __ne__ / __lt__ / __le__ / __gt__ / __ge__ via richcompare
            if (@hasDecl(T, "__eq__") or @hasDecl(T, "__ne__") or @hasDecl(T, "__lt__") or @hasDecl(T, "__le__") or @hasDecl(T, "__gt__") or @hasDecl(T, "__ge__")) {
                obj.tp_richcompare = @ptrCast(&py_richcompare);
            }

            // __hash__
            if (@hasDecl(T, "__hash__")) {
                obj.tp_hash = @ptrCast(&py_hash);
            }

            // Number protocol (__add__, __sub__, __mul__, etc.)
            if (hasNumberMethods()) {
                obj.tp_as_number = &number_methods;
            }

            // Sequence protocol (__len__, __getitem__, __contains__)
            if (hasSequenceMethods()) {
                obj.tp_as_sequence = &sequence_methods;
            }

            // Mapping protocol (__getitem__ with non-integer keys)
            if (hasMappingMethods()) {
                obj.tp_as_mapping = &mapping_methods;
            }

            // Iterator protocol (__iter__)
            if (@hasDecl(T, "__iter__")) {
                obj.tp_iter = @ptrCast(&py_iter);
            }

            // __next__ for iterator objects
            if (@hasDecl(T, "__next__")) {
                obj.tp_iternext = @ptrCast(&py_iternext);
            }

            // Buffer protocol (__buffer__)
            if (hasBufferProtocol()) {
                obj.tp_as_buffer = &buffer_procs;
            }

            // Descriptor protocol (__get__, __set__, __delete__)
            if (@hasDecl(T, "__get__")) {
                obj.tp_descr_get = @ptrCast(&py_descr_get);
            }
            if (@hasDecl(T, "__set__") or @hasDecl(T, "__delete__")) {
                obj.tp_descr_set = @ptrCast(&py_descr_set);
            }

            // __call__ - make instances callable
            if (@hasDecl(T, "__call__")) {
                obj.tp_call = @ptrCast(&py_call);
            }

            // __getattr__ - dynamic attribute access
            // Note: tp_getattro is called for ALL attribute access, so we need to
            // fall back to default behavior for known attributes
            if (@hasDecl(T, "__getattr__")) {
                obj.tp_getattro = @ptrCast(&py_getattro);
            } else if (has_dict_support) {
                // For __dict__ support without custom __getattr__, use Python's generic handler
                obj.tp_getattro = py.c.PyObject_GenericGetAttr;
            }

            // __setattr__ / __delattr__ - dynamic attribute assignment/deletion
            if (@hasDecl(T, "__setattr__") or @hasDecl(T, "__delattr__")) {
                obj.tp_setattro = @ptrCast(&py_setattro);
            } else if (has_dict_support) {
                // For __dict__ support without custom __setattr__, use Python's generic handler
                obj.tp_setattro = py.c.PyObject_GenericSetAttr;
            }

            // Frozen classes - reject all attribute assignment after creation
            if (isFrozen()) {
                obj.tp_setattro = @ptrCast(&py_frozen_setattro);
            }

            // GC support (__traverse__, __clear__)
            if (hasGCSupport()) {
                obj.tp_traverse = @ptrCast(&py_traverse);
                if (@hasDecl(T, "__clear__")) {
                    obj.tp_clear = @ptrCast(&py_clear);
                }
            }

            return obj;
        }

        /// Check if this class is frozen (immutable after creation)
        fn isFrozen() bool {
            if (@hasDecl(T, "__frozen__")) {
                const FrozenType = @TypeOf(T.__frozen__);
                if (FrozenType == bool) {
                    return T.__frozen__;
                }
            }
            return false;
        }

        fn hasBufferProtocol() bool {
            return @hasDecl(T, "__buffer__");
        }

        fn hasGCSupport() bool {
            return @hasDecl(T, "__traverse__");
        }

        fn hasNumberMethods() bool {
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
                // In-place operators
                @hasDecl(T, "__iadd__") or @hasDecl(T, "__isub__") or
                @hasDecl(T, "__imul__") or @hasDecl(T, "__itruediv__") or
                @hasDecl(T, "__ifloordiv__") or @hasDecl(T, "__imod__") or
                @hasDecl(T, "__ipow__") or @hasDecl(T, "__ilshift__") or
                @hasDecl(T, "__irshift__") or @hasDecl(T, "__iand__") or
                @hasDecl(T, "__ior__") or @hasDecl(T, "__ixor__") or
                @hasDecl(T, "__imatmul__") or
                // Reflected operators
                @hasDecl(T, "__radd__") or @hasDecl(T, "__rsub__") or
                @hasDecl(T, "__rmul__") or @hasDecl(T, "__rtruediv__") or
                @hasDecl(T, "__rfloordiv__") or @hasDecl(T, "__rmod__") or
                @hasDecl(T, "__rdivmod__") or
                @hasDecl(T, "__rpow__") or @hasDecl(T, "__rlshift__") or
                @hasDecl(T, "__rrshift__") or @hasDecl(T, "__rand__") or
                @hasDecl(T, "__ror__") or @hasDecl(T, "__rxor__") or
                @hasDecl(T, "__rmatmul__");
        }

        fn hasSequenceMethods() bool {
            return @hasDecl(T, "__len__") or @hasDecl(T, "__getitem__") or @hasDecl(T, "__contains__") or @hasDecl(T, "__reversed__");
        }

        fn hasMappingMethods() bool {
            // Use mapping protocol if __getitem__ exists (for dict-like access)
            return @hasDecl(T, "__getitem__");
        }

        // ====================================================================
        // __new__
        // ====================================================================

        fn py_new(type_obj: ?*py.PyTypeObject, args: ?*py.PyObject, kwds: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = args;
            _ = kwds;
            const t = type_obj orelse return null;
            // Use PyType_GenericAlloc which handles heap types correctly
            // (increments type refcount for heap types)
            const obj = py.PyType_GenericAlloc(t, 0) orelse return null;
            // Zero-initialize our data portion
            const self: *PyWrapper = @ptrCast(@alignCast(obj));
            self.getData().* = std.mem.zeroes(T);
            // Initialize extra fields (dict, weakref) to null
            self.initExtra();
            return obj;
        }

        // ====================================================================
        // __init__ - parse args and set fields
        // ====================================================================

        fn py_init(self_obj: ?*py.PyObject, args: ?*py.PyObject, kwds: ?*py.PyObject) callconv(.c) c_int {
            _ = kwds;
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const py_args = args orelse {
                // No args provided
                if (@hasDecl(T, "__new__")) {
                    // __new__ with no args
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

            // If __new__ is defined, use it for initialization
            if (@hasDecl(T, "__new__")) {
                const NewFn = @TypeOf(T.__new__);
                const new_fn_info = @typeInfo(NewFn).@"fn";
                const new_params = new_fn_info.params;

                if (arg_count != new_params.len) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                    return -1;
                }

                // Parse args for __new__
                const zig_args = parseNewArgs(py_args) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert arguments");
                    return -1;
                };

                self.getData().* = @call(.auto, T.__new__, zig_args);
                return 0;
            }

            // Otherwise use field-based initialization
            if (arg_count != fields.len) {
                py.PyErr_SetString(py.PyExc_TypeError(), "Wrong number of arguments to __init__");
                return -1;
            }

            // Parse each argument and set the corresponding field
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

        // Helper to parse arguments for __new__
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

        // ====================================================================
        // __del__
        // ====================================================================

        fn py_dealloc(self_obj: ?*py.PyObject) callconv(.c) void {
            const obj = self_obj orelse return;
            const self: *PyWrapper = @ptrCast(@alignCast(obj));

            // Get the object's actual type (may be a subclass)
            const obj_type = py.Py_TYPE(obj);

            // For heap types (subclasses), we need to decref the type AFTER tp_free
            // Save the type pointer before freeing
            const tp: ?*py.PyTypeObject = obj_type;
            const is_heaptype = if (tp) |t| (t.tp_flags & py.Py_TPFLAGS_HEAPTYPE) != 0 else false;

            // Clear weak references first (must be done before other cleanup)
            if (has_weakref_support) {
                if (self.getWeakRefList()) |_| {
                    py.PyObject_ClearWeakRefs(obj);
                }
            }

            // Clean up __dict__ if present
            if (has_dict_support) {
                if (self.getDict()) |dict| {
                    py.Py_DecRef(dict);
                    self.setDict(null);
                }
            }

            // Call tp_free from the type to properly deallocate
            if (obj_type) |t| {
                if (t.tp_free) |free_fn| {
                    free_fn(self_obj);
                } else {
                    py.PyObject_Del(self_obj);
                }
            } else {
                py.PyObject_Del(self_obj);
            }

            // For heap types (subclasses), decrement type refcount
            // This balances the incref done in PyType_GenericAlloc/PyObject_Init
            if (is_heaptype) {
                if (tp) |t| {
                    py.Py_DecRef(@ptrCast(t));
                }
            }
        }

        // ====================================================================
        // __repr__ (default)
        // ====================================================================

        fn py_repr(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            _ = self;
            // Default repr - just return the class name
            return py.PyUnicode_FromString(name);
        }

        // ====================================================================
        // __repr__ (custom - calls T.__repr__)
        // ====================================================================

        fn py_magic_repr(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__repr__(self.getDataConst());
            return getConversions().toPy(@TypeOf(result), result);
        }

        // ====================================================================
        // __str__ (custom - calls T.__str__)
        // ====================================================================

        fn py_magic_str(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__str__(self.getDataConst());
            return getConversions().toPy(@TypeOf(result), result);
        }

        // ====================================================================
        // __hash__ (custom - calls T.__hash__)
        // ====================================================================

        fn py_hash(self_obj: ?*py.PyObject) callconv(.c) py.c.Py_hash_t {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            return @intCast(T.__hash__(self.getDataConst()));
        }

        // ====================================================================
        // Rich comparison (__eq__, __ne__, __lt__, __le__, __gt__, __ge__)
        // ====================================================================

        const Py_LT: c_int = 0;
        const Py_LE: c_int = 1;
        const Py_EQ: c_int = 2;
        const Py_NE: c_int = 3;
        const Py_GT: c_int = 4;
        const Py_GE: c_int = 5;

        fn py_richcompare(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, op: c_int) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse {
                // If other is not our type, return NotImplemented
                return py.Py_NotImplemented();
            }));

            // Check if other is actually our type
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
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

        // ====================================================================
        // Number methods (__add__, __sub__, __mul__, __neg__)
        // ====================================================================

        var number_methods: py.c.PyNumberMethods = makeNumberMethods();

        fn makeNumberMethods() py.c.PyNumberMethods {
            var nm: py.c.PyNumberMethods = std.mem.zeroes(py.c.PyNumberMethods);

            if (@hasDecl(T, "__add__")) {
                nm.nb_add = @ptrCast(&py_nb_add);
            }
            if (@hasDecl(T, "__sub__")) {
                nm.nb_subtract = @ptrCast(&py_nb_sub);
            }
            if (@hasDecl(T, "__mul__")) {
                nm.nb_multiply = @ptrCast(&py_nb_mul);
            }
            if (@hasDecl(T, "__neg__")) {
                nm.nb_negative = @ptrCast(&py_nb_neg);
            }
            if (@hasDecl(T, "__truediv__")) {
                nm.nb_true_divide = @ptrCast(&py_nb_truediv);
            }
            if (@hasDecl(T, "__floordiv__")) {
                nm.nb_floor_divide = @ptrCast(&py_nb_floordiv);
            }
            if (@hasDecl(T, "__mod__")) {
                nm.nb_remainder = @ptrCast(&py_nb_mod);
            }
            if (@hasDecl(T, "__divmod__")) {
                nm.nb_divmod = @ptrCast(&py_nb_divmod);
            }
            if (@hasDecl(T, "__bool__")) {
                nm.nb_bool = @ptrCast(&py_nb_bool);
            }
            if (@hasDecl(T, "__pow__")) {
                nm.nb_power = @ptrCast(&py_nb_pow);
            }
            if (@hasDecl(T, "__pos__")) {
                nm.nb_positive = @ptrCast(&py_nb_pos);
            }
            if (@hasDecl(T, "__abs__")) {
                nm.nb_absolute = @ptrCast(&py_nb_abs);
            }
            if (@hasDecl(T, "__invert__")) {
                nm.nb_invert = @ptrCast(&py_nb_invert);
            }
            if (@hasDecl(T, "__lshift__")) {
                nm.nb_lshift = @ptrCast(&py_nb_lshift);
            }
            if (@hasDecl(T, "__rshift__")) {
                nm.nb_rshift = @ptrCast(&py_nb_rshift);
            }
            if (@hasDecl(T, "__and__")) {
                nm.nb_and = @ptrCast(&py_nb_and);
            }
            if (@hasDecl(T, "__or__")) {
                nm.nb_or = @ptrCast(&py_nb_or);
            }
            if (@hasDecl(T, "__xor__")) {
                nm.nb_xor = @ptrCast(&py_nb_xor);
            }
            if (@hasDecl(T, "__matmul__")) {
                nm.nb_matrix_multiply = @ptrCast(&py_nb_matmul);
            }
            if (@hasDecl(T, "__int__")) {
                nm.nb_int = @ptrCast(&py_nb_int);
            }
            if (@hasDecl(T, "__float__")) {
                nm.nb_float = @ptrCast(&py_nb_float);
            }
            if (@hasDecl(T, "__index__")) {
                nm.nb_index = @ptrCast(&py_nb_index);
            }
            // In-place operators
            if (@hasDecl(T, "__iadd__")) {
                nm.nb_inplace_add = @ptrCast(&py_nb_iadd);
            }
            if (@hasDecl(T, "__isub__")) {
                nm.nb_inplace_subtract = @ptrCast(&py_nb_isub);
            }
            if (@hasDecl(T, "__imul__")) {
                nm.nb_inplace_multiply = @ptrCast(&py_nb_imul);
            }
            if (@hasDecl(T, "__itruediv__")) {
                nm.nb_inplace_true_divide = @ptrCast(&py_nb_itruediv);
            }
            if (@hasDecl(T, "__ifloordiv__")) {
                nm.nb_inplace_floor_divide = @ptrCast(&py_nb_ifloordiv);
            }
            if (@hasDecl(T, "__imod__")) {
                nm.nb_inplace_remainder = @ptrCast(&py_nb_imod);
            }
            if (@hasDecl(T, "__ipow__")) {
                nm.nb_inplace_power = @ptrCast(&py_nb_ipow);
            }
            if (@hasDecl(T, "__ilshift__")) {
                nm.nb_inplace_lshift = @ptrCast(&py_nb_ilshift);
            }
            if (@hasDecl(T, "__irshift__")) {
                nm.nb_inplace_rshift = @ptrCast(&py_nb_irshift);
            }
            if (@hasDecl(T, "__iand__")) {
                nm.nb_inplace_and = @ptrCast(&py_nb_iand);
            }
            if (@hasDecl(T, "__ior__")) {
                nm.nb_inplace_or = @ptrCast(&py_nb_ior);
            }
            if (@hasDecl(T, "__ixor__")) {
                nm.nb_inplace_xor = @ptrCast(&py_nb_ixor);
            }
            if (@hasDecl(T, "__imatmul__")) {
                nm.nb_inplace_matrix_multiply = @ptrCast(&py_nb_imatmul);
            }

            return nm;
        }

        fn py_nb_add(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            // Normal case: self + other (both are T)
            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__add__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__add__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            // Reflected case: other + self (self is not T, other is T)
            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__radd__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    // __radd__ takes (self, other) where self is T and other is the left operand
                    const result = T.__radd__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            // Forward case with non-T other
            if (self_is_T and !other_is_T) {
                if (@hasDecl(T, "__add__")) {
                    // Check if __add__ can accept PyObject
                    const AddFn = @TypeOf(T.__add__);
                    const add_params = @typeInfo(AddFn).@"fn".params;
                    if (add_params.len >= 2) {
                        const OtherType = add_params[1].type.?;
                        if (OtherType == ?*py.PyObject or OtherType == *py.PyObject) {
                            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                            const result = T.__add__(self.getDataConst(), other_obj.?);
                            return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                        }
                    }
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_sub(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__sub__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__sub__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rsub__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rsub__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_mul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__mul__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__mul__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rmul__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rmul__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_neg(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__neg__(self.getDataConst());
            return getSelfAwareConverter(T).toPy(T, result);
        }

        fn py_nb_truediv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__truediv__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const TrueDivFn = @TypeOf(T.__truediv__);
                    const RetType = @typeInfo(TrueDivFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__truediv__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__truediv__(self.getDataConst(), other.getDataConst());
                        return getSelfAwareConverter(T).toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rtruediv__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rtruediv__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_floordiv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__floordiv__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const FloorDivFn = @TypeOf(T.__floordiv__);
                    const RetType = @typeInfo(FloorDivFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__floordiv__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__floordiv__(self.getDataConst(), other.getDataConst());
                        return getSelfAwareConverter(T).toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rfloordiv__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rfloordiv__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_mod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__mod__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const ModFn = @TypeOf(T.__mod__);
                    const RetType = @typeInfo(ModFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__mod__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__mod__(self.getDataConst(), other.getDataConst());
                        return getSelfAwareConverter(T).toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rmod__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rmod__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_divmod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__divmod__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const DivmodFn = @TypeOf(T.__divmod__);
                    const RetType = @typeInfo(DivmodFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__divmod__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ZeroDivisionError(), msg.ptr);
                            return null;
                        };
                        // __divmod__ returns a tuple (quotient, remainder)
                        return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__divmod__(self.getDataConst(), other.getDataConst());
                        return getSelfAwareConverter(T).toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rdivmod__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rdivmod__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_bool(self_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const result = T.__bool__(self.getDataConst());
            return if (result) 1 else 0;
        }

        fn py_nb_pow(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, mod_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = mod_obj; // We don't support modular exponentiation for now
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__pow__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const PowFn = @TypeOf(T.__pow__);
                    const RetType = @typeInfo(PowFn).@"fn".return_type.?;
                    if (@typeInfo(RetType) == .error_union) {
                        const result = T.__pow__(self.getDataConst(), other.getDataConst()) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_ValueError(), msg.ptr);
                            return null;
                        };
                        return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                    } else {
                        const result = T.__pow__(self.getDataConst(), other.getDataConst());
                        return getSelfAwareConverter(T).toPy(RetType, result);
                    }
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rpow__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rpow__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_pos(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__pos__(self.getDataConst());
            return getSelfAwareConverter(T).toPy(T, result);
        }

        fn py_nb_abs(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__abs__(self.getDataConst());
            return getSelfAwareConverter(T).toPy(T, result);
        }

        fn py_nb_invert(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__invert__(self.getDataConst());
            return getSelfAwareConverter(T).toPy(T, result);
        }

        fn py_nb_lshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__lshift__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__lshift__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rlshift__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rlshift__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_rshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__rshift__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rshift__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rrshift__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rrshift__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_and(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__and__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__and__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rand__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rand__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_or(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__or__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__or__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__ror__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__ror__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_xor(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__xor__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__xor__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(T, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rxor__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rxor__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_matmul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self_is_T = py.PyObject_TypeCheck(self_obj.?, &type_object);
            const other_is_T = py.PyObject_TypeCheck(other_obj.?, &type_object);

            if (self_is_T and other_is_T) {
                if (@hasDecl(T, "__matmul__")) {
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const MatmulFn = @TypeOf(T.__matmul__);
                    const RetType = @typeInfo(MatmulFn).@"fn".return_type.?;
                    const result = T.__matmul__(self.getDataConst(), other.getDataConst());
                    return getSelfAwareConverter(T).toPy(RetType, result);
                }
            }

            if (!self_is_T and other_is_T) {
                if (@hasDecl(T, "__rmatmul__")) {
                    const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
                    const result = T.__rmatmul__(other.getDataConst(), self_obj.?);
                    return getSelfAwareConverter(T).toPy(@TypeOf(result), result);
                }
            }

            return py.Py_NotImplemented();
        }

        fn py_nb_int(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__int__(self.getDataConst());
            return getConversions().toPy(@TypeOf(result), result);
        }

        fn py_nb_float(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__float__(self.getDataConst());
            return getConversions().toPy(@TypeOf(result), result);
        }

        fn py_nb_index(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const result = T.__index__(self.getDataConst());
            return getConversions().toPy(@TypeOf(result), result);
        }

        // In-place operators - these modify self and return self
        fn py_nb_iadd(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__iadd__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_isub(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__isub__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_imul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__imul__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_itruediv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__itruediv__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ifloordiv(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__ifloordiv__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_imod(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__imod__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ipow(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject, mod_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = mod_obj;
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__ipow__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ilshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__ilshift__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_irshift(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__irshift__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_iand(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__iand__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ior(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__ior__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_ixor(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__ixor__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        fn py_nb_imatmul(self_obj: ?*py.PyObject, other_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const other: *PyWrapper = @ptrCast(@alignCast(other_obj orelse return null));
            if (!py.PyObject_TypeCheck(other_obj.?, &type_object)) {
                return py.Py_NotImplemented();
            }
            T.__imatmul__(self.getData(), other.getDataConst());
            py.Py_IncRef(self_obj);
            return self_obj;
        }

        // ====================================================================
        // Sequence methods (__len__, __getitem__, __contains__)
        // ====================================================================

        var sequence_methods: py.PySequenceMethods = makeSequenceMethods();

        fn makeSequenceMethods() py.PySequenceMethods {
            var sm: py.PySequenceMethods = std.mem.zeroes(py.PySequenceMethods);

            if (@hasDecl(T, "__len__")) {
                sm.sq_length = @ptrCast(&py_sq_length);
            }
            if (@hasDecl(T, "__getitem__")) {
                sm.sq_item = @ptrCast(&py_sq_item);
            }
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) {
                sm.sq_ass_item = @ptrCast(&py_sq_ass_item);
            }
            if (@hasDecl(T, "__contains__")) {
                sm.sq_contains = @ptrCast(&py_sq_contains);
            }

            return sm;
        }

        fn py_sq_length(self_obj: ?*py.PyObject) callconv(.c) py.Py_ssize_t {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const result = T.__len__(self.getDataConst());
            return @intCast(result);
        }

        fn py_sq_item(self_obj: ?*py.PyObject, index: py.Py_ssize_t) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            // Call the Zig __getitem__ with an integer index
            const GetItemRetType = @typeInfo(@TypeOf(T.__getitem__)).@"fn".return_type.?;
            if (@typeInfo(GetItemRetType) == .error_union) {
                const result = T.__getitem__(self.getDataConst(), @intCast(index)) catch |err| {
                    const msg = @errorName(err);
                    py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                    return null;
                };
                return getConversions().toPy(@TypeOf(result), result);
            } else {
                const result = T.__getitem__(self.getDataConst(), @intCast(index));
                return getConversions().toPy(GetItemRetType, result);
            }
        }

        fn py_sq_contains(self_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const value = value_obj orelse return -1;

            // Get the element type from __contains__ signature
            const ContainsFn = @TypeOf(T.__contains__);
            const fn_info = @typeInfo(ContainsFn).@"fn";
            const ElemType = fn_info.params[1].type.?;

            const elem = getConversions().fromPy(ElemType, value) catch {
                return 0; // Type mismatch means not contained
            };

            const result = T.__contains__(self.getDataConst(), elem);
            return if (result) 1 else 0;
        }

        // sq_ass_item: handles both __setitem__ (value != null) and __delitem__ (value == null) for integer indices
        fn py_sq_ass_item(self_obj: ?*py.PyObject, index: py.Py_ssize_t, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));

            if (value_obj) |value| {
                // __setitem__ case
                if (!@hasDecl(T, "__setitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item assignment");
                    return -1;
                }

                const SetItemFn = @TypeOf(T.__setitem__);
                const set_fn_info = @typeInfo(SetItemFn).@"fn";
                const ValueType = set_fn_info.params[2].type.?;

                const zig_value = getConversions().fromPy(ValueType, value) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "invalid value type for __setitem__");
                    return -1;
                };

                const SetRetType = set_fn_info.return_type.?;
                if (@typeInfo(SetRetType) == .error_union) {
                    T.__setitem__(self.getData(), @intCast(index), zig_value) catch |err| {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                        return -1;
                    };
                } else {
                    T.__setitem__(self.getData(), @intCast(index), zig_value);
                }
                return 0;
            } else {
                // __delitem__ case
                if (!@hasDecl(T, "__delitem__")) {
                    py.PyErr_SetString(py.PyExc_TypeError(), "object does not support item deletion");
                    return -1;
                }

                const DelRetType = @typeInfo(@TypeOf(T.__delitem__)).@"fn".return_type.?;
                if (@typeInfo(DelRetType) == .error_union) {
                    T.__delitem__(self.getData(), @intCast(index)) catch |err| {
                        const msg = @errorName(err);
                        py.PyErr_SetString(py.PyExc_IndexError(), msg.ptr);
                        return -1;
                    };
                } else {
                    T.__delitem__(self.getData(), @intCast(index));
                }
                return 0;
            }
        }

        // ====================================================================
        // Mapping methods (__getitem__ with any key type)
        // ====================================================================

        var mapping_methods: py.PyMappingMethods = makeMappingMethods();

        fn makeMappingMethods() py.PyMappingMethods {
            var mm: py.PyMappingMethods = std.mem.zeroes(py.PyMappingMethods);

            if (@hasDecl(T, "__len__")) {
                mm.mp_length = @ptrCast(&py_sq_length);
            }
            if (@hasDecl(T, "__getitem__")) {
                mm.mp_subscript = @ptrCast(&py_mp_subscript);
            }
            if (@hasDecl(T, "__setitem__") or @hasDecl(T, "__delitem__")) {
                mm.mp_ass_subscript = @ptrCast(&py_mp_ass_subscript);
            }

            return mm;
        }

        fn py_mp_subscript(self_obj: ?*py.PyObject, key_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const key = key_obj orelse return null;

            // Get the key type from __getitem__ signature
            const GetItemFn = @TypeOf(T.__getitem__);
            const fn_info = @typeInfo(GetItemFn).@"fn";
            const KeyType = fn_info.params[1].type.?;

            // Determine if key type is integer-like (for proper exception type)
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

        // mp_ass_subscript: handles __setitem__ and __delitem__ for any key type
        fn py_mp_ass_subscript(self_obj: ?*py.PyObject, key_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const key = key_obj orelse return -1;

            if (value_obj) |value| {
                // __setitem__ case
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
                // __delitem__ case
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

        // ====================================================================
        // Iterator protocol (__iter__, __next__)
        // ====================================================================

        fn py_iter(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            // Call T.__iter__ which may modify self (e.g., reset iteration index)
            const result = T.__iter__(self.getData());
            const ResultType = @TypeOf(result);

            // Check if __iter__ returns *T (self) or T (new value)
            const result_info = @typeInfo(ResultType);
            if (result_info == .pointer and result_info.pointer.child == T) {
                // Return self with incremented refcount
                py.Py_IncRef(self_obj);
                return self_obj;
            } else {
                // Return a new object
                return getSelfAwareConverter(T).toPy(ResultType, result);
            }
        }

        fn py_iternext(self_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            // Call T.__next__ which should return ?ItemType (null signals StopIteration)
            const result = T.__next__(self.getData());
            if (result) |value| {
                return getConversions().toPy(@TypeOf(value), value);
            } else {
                // Signal StopIteration by returning NULL without setting an exception
                // (Python detects this as end of iteration)
                return null;
            }
        }

        // ====================================================================
        // Buffer protocol (__buffer__)
        // ====================================================================

        var buffer_procs: py.PyBufferProcs = makeBufferProcs();

        fn makeBufferProcs() py.PyBufferProcs {
            var bp: py.PyBufferProcs = std.mem.zeroes(py.PyBufferProcs);
            bp.bf_getbuffer = @ptrCast(&py_bf_getbuffer);
            bp.bf_releasebuffer = @ptrCast(&py_bf_releasebuffer);
            return bp;
        }

        fn py_bf_getbuffer(self_obj: ?*py.PyObject, view: ?*py.Py_buffer, flags: c_int) callconv(.c) c_int {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const v = view orelse return -1;

            // Call T.__buffer__ to get buffer info
            const info = T.__buffer__(self.getData());

            // Fill in the view structure
            v.buf = @ptrCast(info.ptr);
            v.obj = self_obj;
            py.Py_IncRef(self_obj); // Hold reference while buffer is in use
            v.len = @intCast(info.len);
            v.itemsize = @intCast(info.itemsize);
            v.readonly = if (info.readonly) 1 else 0;
            v.ndim = @intCast(info.ndim);
            v.format = if ((flags & py.PyBUF_FORMAT) != 0) info.format else null;
            v.shape = if ((flags & py.PyBUF_ND) != 0) info.shape else null;
            v.strides = if ((flags & py.PyBUF_STRIDES) != 0) info.strides else null;
            v.suboffsets = null;
            v.internal = null;

            return 0;
        }

        fn py_bf_releasebuffer(self_obj: ?*py.PyObject, view: ?*py.Py_buffer) callconv(.c) void {
            _ = self_obj;
            _ = view;
            // Nothing to do for simple buffers - reference is released automatically
        }

        // ====================================================================
        // Descriptor protocol (__get__, __set__, __delete__)
        // ====================================================================

        /// tp_descr_get: Called when descriptor is accessed on an object
        /// __get__(self, obj, type) -> value
        /// - self: the descriptor instance
        /// - obj: the instance the descriptor is accessed through (None if accessed on class)
        /// - type: the class the descriptor is accessed through
        fn py_descr_get(descr_obj: ?*py.PyObject, obj: ?*py.PyObject, obj_type: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            const descr: *PyWrapper = @ptrCast(@alignCast(descr_obj orelse return null));

            // Get the __get__ function signature to determine parameter count
            const GetFn = @TypeOf(T.__get__);
            const get_params = @typeInfo(GetFn).@"fn".params;

            // Call T.__get__ with appropriate arguments
            if (get_params.len == 1) {
                // __get__(self) - simplest form
                const result = T.__get__(descr.getDataConst());
                return getConversions().toPy(@TypeOf(result), result);
            } else if (get_params.len == 2) {
                // __get__(self, obj) - obj may be null (class access)
                const result = T.__get__(descr.getDataConst(), obj);
                return getConversions().toPy(@TypeOf(result), result);
            } else if (get_params.len == 3) {
                // __get__(self, obj, type) - full descriptor protocol
                const result = T.__get__(descr.getDataConst(), obj, obj_type);
                return getConversions().toPy(@TypeOf(result), result);
            } else {
                py.PyErr_SetString(py.PyExc_TypeError(), "__get__ must take 1-3 parameters");
                return null;
            }
        }

        /// tp_descr_set: Called when descriptor is set or deleted on an object
        /// __set__(self, obj, value) - called when setting
        /// __delete__(self, obj) - called when deleting (value is null)
        fn py_descr_set(descr_obj: ?*py.PyObject, obj: ?*py.PyObject, value: ?*py.PyObject) callconv(.c) c_int {
            const descr: *PyWrapper = @ptrCast(@alignCast(descr_obj orelse return -1));
            const target = obj orelse {
                py.PyErr_SetString(py.PyExc_TypeError(), "descriptor requires an object");
                return -1;
            };

            if (value) |val| {
                // __set__ case
                if (!@hasDecl(T, "__set__")) {
                    py.PyErr_SetString(py.PyExc_AttributeError(), "descriptor does not support assignment");
                    return -1;
                }

                // Get the value type from __set__ signature
                const SetFn = @TypeOf(T.__set__);
                const set_params = @typeInfo(SetFn).@"fn".params;
                const ValueType = set_params[2].type.?;

                const zig_value = getConversions().fromPy(ValueType, val) catch {
                    py.PyErr_SetString(py.PyExc_TypeError(), "invalid value type for descriptor");
                    return -1;
                };

                // Call __set__(self, obj, value)
                T.__set__(descr.getData(), target, zig_value);
                return 0;
            } else {
                // __delete__ case
                if (!@hasDecl(T, "__delete__")) {
                    py.PyErr_SetString(py.PyExc_AttributeError(), "descriptor does not support deletion");
                    return -1;
                }

                // Call __delete__(self, obj)
                T.__delete__(descr.getData(), target);
                return 0;
            }
        }

        // ====================================================================
        // __getattr__ / __setattr__ / __delattr__ - dynamic attribute access
        // ====================================================================

        /// tp_getattro: Called for ALL attribute access
        /// We first try the default attribute lookup, and if it fails with AttributeError,
        /// we call __getattr__ as a fallback
        fn py_getattro(self_obj: ?*py.PyObject, name_obj: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            // First, try the default attribute lookup (methods, properties, etc.)
            const result = py.PyObject_GenericGetAttr(self_obj, name_obj);
            if (result != null) {
                return result;
            }

            // Check if the error is AttributeError - only then call __getattr__
            if (py.PyErr_ExceptionMatches(py.PyExc_AttributeError()) == 0) {
                // Some other error occurred, propagate it
                return null;
            }

            // Clear the AttributeError and call __getattr__
            py.PyErr_Clear();

            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
            const attr_name = getConversions().fromPy([]const u8, name_obj.?) catch {
                py.PyErr_SetString(py.PyExc_TypeError(), "attribute name must be a string");
                return null;
            };

            // Call T.__getattr__(self, name)
            const GetAttrFn = @TypeOf(T.__getattr__);
            const RetType = @typeInfo(GetAttrFn).@"fn".return_type.?;

            if (@typeInfo(RetType) == .error_union) {
                const attr_result = T.__getattr__(self.getDataConst(), attr_name) catch |err| {
                    const msg = @errorName(err);
                    py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                    return null;
                };
                return getConversions().toPy(@TypeOf(attr_result), attr_result);
            } else if (@typeInfo(RetType) == .optional) {
                if (T.__getattr__(self.getDataConst(), attr_name)) |attr_result| {
                    return getConversions().toPy(@TypeOf(attr_result), attr_result);
                } else {
                    py.PyErr_SetString(py.PyExc_AttributeError(), "attribute not found");
                    return null;
                }
            } else {
                const attr_result = T.__getattr__(self.getDataConst(), attr_name);
                return getConversions().toPy(RetType, attr_result);
            }
        }

        /// tp_setattro: Called for attribute assignment and deletion
        /// We first try __setattr__/__delattr__ if defined, otherwise fall back to default
        fn py_setattro(self_obj: ?*py.PyObject, name_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const attr_name = getConversions().fromPy([]const u8, name_obj.?) catch {
                py.PyErr_SetString(py.PyExc_TypeError(), "attribute name must be a string");
                return -1;
            };

            if (value_obj) |value| {
                // __setattr__ case
                if (@hasDecl(T, "__setattr__")) {
                    const SetAttrFn = @TypeOf(T.__setattr__);
                    const set_params = @typeInfo(SetAttrFn).@"fn".params;
                    const RetType = @typeInfo(SetAttrFn).@"fn".return_type.?;

                    // Check if __setattr__ takes a PyObject or needs type conversion
                    if (set_params.len >= 3) {
                        const ValueType = set_params[2].type.?;
                        if (ValueType == ?*py.PyObject or ValueType == *py.PyObject) {
                            // Pass raw PyObject
                            if (@typeInfo(RetType) == .error_union) {
                                T.__setattr__(self.getData(), attr_name, value) catch |err| {
                                    const msg = @errorName(err);
                                    py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                                    return -1;
                                };
                            } else {
                                T.__setattr__(self.getData(), attr_name, value);
                            }
                            return 0;
                        }
                    }
                }
                // Fall back to default behavior
                return py.PyObject_GenericSetAttr(self_obj, name_obj, value_obj);
            } else {
                // __delattr__ case
                if (@hasDecl(T, "__delattr__")) {
                    const DelAttrFn = @TypeOf(T.__delattr__);
                    const RetType = @typeInfo(DelAttrFn).@"fn".return_type.?;

                    if (@typeInfo(RetType) == .error_union) {
                        T.__delattr__(self.getData(), attr_name) catch |err| {
                            const msg = @errorName(err);
                            py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
                            return -1;
                        };
                    } else {
                        T.__delattr__(self.getData(), attr_name);
                    }
                    return 0;
                }
                // Fall back to default behavior
                return py.PyObject_GenericSetAttr(self_obj, name_obj, value_obj);
            }
        }

        // ====================================================================
        // Frozen class support - reject all attribute assignment
        // ====================================================================

        fn py_frozen_setattro(self_obj: ?*py.PyObject, name_obj: ?*py.PyObject, value_obj: ?*py.PyObject) callconv(.c) c_int {
            _ = self_obj;
            _ = value_obj;

            // Get the attribute name for a better error message
            var size: py.Py_ssize_t = 0;
            const attr_name_ptr: ?[*]const u8 = @ptrCast(py.c.PyUnicode_AsUTF8AndSize(name_obj, &size));

            if (attr_name_ptr) |attr_name| {
                // Build error message with attribute name
                var buf: [256]u8 = undefined;
                const msg = std.fmt.bufPrintZ(&buf, "cannot set attribute '{s}' on frozen class '{s}'", .{ attr_name[0..@intCast(size)], name }) catch "cannot modify frozen class";
                py.PyErr_SetString(py.PyExc_AttributeError(), msg.ptr);
            } else {
                py.PyErr_SetString(py.PyExc_AttributeError(), "cannot modify frozen class");
            }
            return -1;
        }

        // ====================================================================
        // __call__ - make instances callable
        // ====================================================================

        fn py_call(self_obj: ?*py.PyObject, args: ?*py.PyObject, kwargs: ?*py.PyObject) callconv(.c) ?*py.PyObject {
            _ = kwargs; // TODO: support kwargs in __call__
            const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));

            // Parse arguments (first param is self)
            const extra_args = parseCallArgs(args) catch |err| {
                const msg = @errorName(err);
                py.PyErr_SetString(py.PyExc_TypeError(), msg.ptr);
                return null;
            };

            // Call __call__ with self and extra args
            const result = callCallMethod(self.getData(), extra_args);

            // Handle return
            return handleCallReturn(result);
        }

        fn parseCallArgs(py_args: ?*py.PyObject) !CallArgsTuple() {
            const CallFn = @TypeOf(T.__call__);
            const call_params = @typeInfo(CallFn).@"fn".params;
            const extra_param_count = call_params.len - 1; // Skip self

            var result: CallArgsTuple() = undefined;

            if (extra_param_count == 0) {
                return result;
            }

            const args_tuple = py_args orelse return error.MissingArguments;
            const arg_count = py.PyTuple_Size(args_tuple);

            if (arg_count != extra_param_count) {
                return error.WrongArgumentCount;
            }

            comptime var i: usize = 0;
            inline for (1..call_params.len) |param_idx| {
                const item = py.PyTuple_GetItem(args_tuple, @intCast(i)) orelse return error.InvalidArgument;
                result[i] = try getSelfAwareConverter(T).fromPy(call_params[param_idx].type.?, item);
                i += 1;
            }

            return result;
        }

        fn CallArgsTuple() type {
            const CallFn = @TypeOf(T.__call__);
            const call_params = @typeInfo(CallFn).@"fn".params;
            if (call_params.len <= 1) return std.meta.Tuple(&[_]type{});
            var types: [call_params.len - 1]type = undefined;
            for (1..call_params.len) |i| {
                types[i - 1] = call_params[i].type.?;
            }
            return std.meta.Tuple(&types);
        }

        fn callCallMethod(self_ptr: anytype, extra: CallArgsTuple()) @typeInfo(@TypeOf(T.__call__)).@"fn".return_type.? {
            const CallFn = @TypeOf(T.__call__);
            const call_params = @typeInfo(CallFn).@"fn".params;
            if (call_params.len == 1) {
                return @call(.auto, T.__call__, .{self_ptr});
            } else {
                return @call(.auto, T.__call__, .{self_ptr} ++ extra);
            }
        }

        fn handleCallReturn(result: @typeInfo(@TypeOf(T.__call__)).@"fn".return_type.?) ?*py.PyObject {
            const CallFn = @TypeOf(T.__call__);
            const ReturnType = @typeInfo(CallFn).@"fn".return_type.?;
            const rt_info = @typeInfo(ReturnType);

            if (rt_info == .error_union) {
                if (result) |value| {
                    return getConversions().toPy(@TypeOf(value), value);
                } else |err| {
                    const msg = @errorName(err);
                    py.PyErr_SetString(py.PyExc_RuntimeError(), msg.ptr);
                    return null;
                }
            } else if (ReturnType == void) {
                return py.Py_RETURN_NONE();
            } else {
                return getConversions().toPy(ReturnType, result);
            }
        }

        // ====================================================================
        // Getters and Setters (generated for each field, or custom get_X/set_X)
        // ====================================================================

        // Check if struct has custom getter (get_fieldname) or setter (set_fieldname)
        fn hasCustomGetter(comptime field_name: []const u8) bool {
            const getter_name = "get_" ++ field_name;
            return @hasDecl(T, getter_name);
        }

        fn hasCustomSetter(comptime field_name: []const u8) bool {
            const setter_name = "set_" ++ field_name;
            return @hasDecl(T, setter_name);
        }

        // Detect computed properties: get_X declarations that don't match field names
        fn countComputedProperties() usize {
            const type_decls = @typeInfo(T).@"struct".decls;
            var count: usize = 0;
            for (type_decls) |decl| {
                if (decl.name.len > 4 and std.mem.startsWith(u8, decl.name, "get_")) {
                    const prop_name = decl.name[4..];
                    // Check if this matches a field name
                    var is_field = false;
                    for (fields) |field| {
                        if (std.mem.eql(u8, field.name, prop_name)) {
                            is_field = true;
                            break;
                        }
                    }
                    if (!is_field) {
                        count += 1;
                    }
                }
            }
            return count;
        }

        const computed_props_count = countComputedProperties();
        const total_getset_count = fields.len + computed_props_count + 1; // +1 for sentinel

        var getset: [total_getset_count]py.PyGetSetDef = blk: {
            var gs: [total_getset_count]py.PyGetSetDef = undefined;

            // First, add field-based getters/setters
            // For frozen classes, setters are null (read-only)
            for (fields, 0..) |field, idx| {
                gs[idx] = .{
                    .name = @ptrCast(field.name.ptr),
                    .get = @ptrCast(generateGetter(field.name, field.type)),
                    .set = if (isFrozen()) null else @ptrCast(generateSetter(field.name, field.type)),
                    .doc = getPropertyDoc(field.name),
                    .closure = null,
                };
            }

            // Then add computed properties
            var comp_idx: usize = fields.len;
            const type_decls = @typeInfo(T).@"struct".decls;
            for (type_decls) |decl| {
                if (decl.name.len > 4 and std.mem.startsWith(u8, decl.name, "get_")) {
                    const prop_name = decl.name[4..];
                    // Check if this matches a field name
                    var is_field = false;
                    for (fields) |field| {
                        if (std.mem.eql(u8, field.name, prop_name)) {
                            is_field = true;
                            break;
                        }
                    }
                    if (!is_field) {
                        // This is a computed property
                        // For frozen classes, setters are null (read-only)
                        gs[comp_idx] = .{
                            .name = @ptrCast(prop_name.ptr),
                            .get = @ptrCast(generateComputedGetter(prop_name)),
                            .set = if (isFrozen()) null else @ptrCast(generateComputedSetter(prop_name)),
                            .doc = getPropertyDoc(prop_name),
                            .closure = null,
                        };
                        comp_idx += 1;
                    }
                }
            }

            // Sentinel
            gs[total_getset_count - 1] = .{
                .name = null,
                .get = null,
                .set = null,
                .doc = null,
                .closure = null,
            };

            break :blk gs;
        };

        fn generateGetter(comptime field_name: []const u8, comptime FieldType: type) *const fn (?*py.PyObject, ?*anyopaque) callconv(.c) ?*py.PyObject {
            // Check for custom getter (get_fieldname)
            if (comptime hasCustomGetter(field_name)) {
                return struct {
                    fn get(self_obj: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) ?*py.PyObject {
                        _ = closure;
                        const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                        const custom_getter = @field(T, "get_" ++ field_name);
                        const result = custom_getter(self.getDataConst());
                        return getConversions().toPy(@TypeOf(result), result);
                    }
                }.get;
            }
            // Default getter - just return field value
            return struct {
                fn get(self_obj: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) ?*py.PyObject {
                    _ = closure;
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const value = @field(self.getDataConst().*, field_name);
                    return getConversions().toPy(FieldType, value);
                }
            }.get;
        }

        fn generateSetter(comptime field_name: []const u8, comptime FieldType: type) *const fn (?*py.PyObject, ?*py.PyObject, ?*anyopaque) callconv(.c) c_int {
            // Check for custom setter (set_fieldname)
            if (comptime hasCustomSetter(field_name)) {
                return struct {
                    fn set(self_obj: ?*py.PyObject, value: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) c_int {
                        _ = closure;
                        const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
                        const py_value = value orelse {
                            py.PyErr_SetString(py.PyExc_AttributeError(), "Cannot delete attribute");
                            return -1;
                        };
                        const custom_setter = @field(T, "set_" ++ field_name);
                        const SetterType = @TypeOf(custom_setter);
                        const setter_info = @typeInfo(SetterType).@"fn";
                        const ValueType = setter_info.params[1].type.?;
                        const converted = getConversions().fromPy(ValueType, py_value) catch {
                            py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert value for: " ++ field_name);
                            return -1;
                        };
                        // Call custom setter - check if it returns error
                        const RetType = setter_info.return_type orelse void;
                        if (@typeInfo(RetType) == .error_union) {
                            custom_setter(self.getData(), converted) catch |err| {
                                const msg = @errorName(err);
                                py.PyErr_SetString(py.PyExc_ValueError(), msg.ptr);
                                return -1;
                            };
                        } else {
                            custom_setter(self.getData(), converted);
                        }
                        return 0;
                    }
                }.set;
            }
            // Default setter - just set field value
            return struct {
                fn set(self_obj: ?*py.PyObject, value: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) c_int {
                    _ = closure;
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
                    const py_value = value orelse {
                        py.PyErr_SetString(py.PyExc_AttributeError(), "Cannot delete attribute");
                        return -1;
                    };
                    @field(self.getData().*, field_name) = getConversions().fromPy(FieldType, py_value) catch {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert value for: " ++ field_name);
                        return -1;
                    };
                    return 0;
                }
            }.set;
        }

        // Generate getter for computed property (get_X where X is not a field)
        fn generateComputedGetter(comptime prop_name: []const u8) *const fn (?*py.PyObject, ?*anyopaque) callconv(.c) ?*py.PyObject {
            const getter_name = "get_" ++ prop_name;
            return struct {
                fn get(self_obj: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) ?*py.PyObject {
                    _ = closure;
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return null));
                    const getter = @field(T, getter_name);
                    const result = getter(self.getDataConst());
                    return getConversions().toPy(@TypeOf(result), result);
                }
            }.get;
        }

        // Generate setter for computed property (set_X where X is not a field)
        fn generateComputedSetter(comptime prop_name: []const u8) ?*const fn (?*py.PyObject, ?*py.PyObject, ?*anyopaque) callconv(.c) c_int {
            const setter_name = "set_" ++ prop_name;
            if (!@hasDecl(T, setter_name)) {
                // No setter - read-only property
                return null;
            }
            return struct {
                fn set(self_obj: ?*py.PyObject, value: ?*py.PyObject, closure: ?*anyopaque) callconv(.c) c_int {
                    _ = closure;
                    const self: *PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
                    const py_value = value orelse {
                        py.PyErr_SetString(py.PyExc_AttributeError(), "Cannot delete property: " ++ prop_name);
                        return -1;
                    };
                    const setter = @field(T, setter_name);
                    const SetterType = @TypeOf(setter);
                    const setter_info = @typeInfo(SetterType).@"fn";
                    const ValueType = setter_info.params[1].type.?;
                    const converted = getConversions().fromPy(ValueType, py_value) catch {
                        py.PyErr_SetString(py.PyExc_TypeError(), "Failed to convert value for property: " ++ prop_name);
                        return -1;
                    };
                    setter(self.getData(), converted);
                    return 0;
                }
            }.set;
        }

        // ====================================================================
        // Methods (generated from pub fn declarations)
        // ====================================================================

        const decls = struct_info.decls;
        const method_count = countMethods();
        const static_method_count = countStaticMethods();
        const class_method_count = countClassMethods();
        const total_method_count = method_count + static_method_count + class_method_count;

        fn countMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isInstanceMethod(decl.name)) count += 1;
            }
            return count;
        }

        fn countStaticMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isStaticMethod(decl.name)) count += 1;
            }
            return count;
        }

        fn countClassMethods() usize {
            var count: usize = 0;
            for (decls) |decl| {
                if (isClassMethod(decl.name)) count += 1;
            }
            return count;
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

        /// Get method docstring from method_name__doc__ declaration if it exists
        fn getMethodDoc(comptime method_name: []const u8) ?[*:0]const u8 {
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

        /// Get property docstring from property_name__doc__ declaration if it exists
        fn getPropertyDoc(comptime prop_name: []const u8) ?[*:0]const u8 {
            const doc_name = prop_name ++ "__doc__";
            if (@hasDecl(T, doc_name)) {
                const DocType = @TypeOf(@field(T, doc_name));
                if (DocType != [*:0]const u8) {
                    @compileError(doc_name ++ " must be declared as [*:0]const u8, e.g.: pub const " ++ doc_name ++ ": [*:0]const u8 = \"...\";");
                }
                return @field(T, doc_name);
            }
            return null;
        }

        var methods: [total_method_count + 1]py.PyMethodDef = blk: {
            var m: [total_method_count + 1]py.PyMethodDef = undefined;
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
            m[total_method_count] = .{
                .ml_name = null,
                .ml_meth = null,
                .ml_flags = 0,
                .ml_doc = null,
            };

            break :blk m;
        };

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

        // ====================================================================
        // Helper to extract Zig data from a Python object
        // ====================================================================

        pub fn unwrap(obj: *py.PyObject) ?*T {
            if (!py.PyObject_TypeCheck(obj, &type_object)) {
                return null;
            }
            const wrapper: *PyWrapper = @ptrCast(@alignCast(obj));
            return wrapper.getData();
        }

        pub fn unwrapConst(obj: *py.PyObject) ?*const T {
            if (!py.PyObject_TypeCheck(obj, &type_object)) {
                return null;
            }
            const wrapper: *const PyWrapper = @ptrCast(@alignCast(obj));
            return wrapper.getDataConst();
        }

        // ====================================================================
        // GC support (__traverse__, __clear__)
        // ====================================================================

        /// tp_traverse: Called by GC to discover references
        fn py_traverse(self_obj: ?*py.PyObject, visit: *const fn (?*py.PyObject, ?*anyopaque) callconv(.c) c_int, arg: ?*anyopaque) callconv(.c) c_int {
            if (self_obj == null) return 0;

            const self_ptr: *PyWrapper = @ptrCast(@alignCast(self_obj.?));
            const self = self_ptr.getData();

            // Create visitor struct
            const visitor = root.GCVisitor{ .visit = visit, .arg = arg };

            // Call user's __traverse__ with the visitor
            if (@hasDecl(T, "__traverse__")) {
                return T.__traverse__(self, visitor);
            }
            return 0;
        }

        /// tp_clear: Called by GC to break reference cycles
        fn py_clear(self_obj: ?*py.PyObject) callconv(.c) c_int {
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

/// Extract a Zig value from a Python object if it's a wrapped class
pub fn unwrap(comptime T: type, obj: *py.PyObject) ?*T {
    // This requires knowing the type was wrapped - we'll enhance this later
    _ = obj;
    return null;
}

/// Create a Python tuple containing the field names of a Zig struct (for __slots__)
pub fn createSlotsTuple(comptime T: type) ?*py.PyObject {
    const info = @typeInfo(T);
    if (info != .@"struct") return null;

    const fields = info.@"struct".fields;
    const tuple = py.PyTuple_New(@intCast(fields.len)) orelse return null;

    inline for (fields, 0..) |field, i| {
        const name_str = py.PyUnicode_FromString(@ptrCast(field.name.ptr)) orelse {
            py.Py_DecRef(tuple);
            return null;
        };
        // PyTuple_SetItem steals the reference
        if (py.PyTuple_SetItem(tuple, @intCast(i), name_str) < 0) {
            py.Py_DecRef(tuple);
            return null;
        }
    }

    return tuple;
}

/// Add class attributes (declarations starting with "classattr_") to the type's dict
/// Returns true on success, false on error
pub fn addClassAttributes(comptime T: type, type_dict: *py.PyObject) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return true;

    const decls = info.@"struct".decls;
    const Conv = root.Conversions;

    inline for (decls) |decl| {
        const prefix = "classattr_";
        if (decl.name.len > prefix.len and std.mem.startsWith(u8, decl.name, prefix)) {
            const attr_name = decl.name[prefix.len..];
            const value = @field(T, decl.name);
            const ValueType = @TypeOf(value);

            // Convert the value to a Python object
            const py_value = Conv.toPy(ValueType, value) orelse {
                return false;
            };

            // Add to the type dict
            if (py.PyDict_SetItemString(type_dict, attr_name.ptr, py_value) < 0) {
                py.Py_DecRef(py_value);
                return false;
            }
            py.Py_DecRef(py_value);
        }
    }

    return true;
}
