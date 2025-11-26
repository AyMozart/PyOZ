//! Module creation and management for PyOZ
//!
//! This module provides a high-level API for creating Python extension modules.

const std = @import("std");
const py = @import("python.zig");
const root = @import("root.zig");

/// A wrapper around a Python module object
pub const Module = struct {
    ptr: *py.PyObject,

    const Self = @This();

    /// Create a new module from a module definition
    pub fn create(def: *py.PyModuleDef) !Self {
        const module = py.PyModule_Create(def) orelse {
            return root.PyErr.RuntimeError;
        };
        return .{ .ptr = module };
    }

    /// Get the underlying PyObject pointer
    pub fn obj(self: Self) *py.PyObject {
        return self.ptr;
    }

    /// Add an integer constant to the module
    pub fn addIntConstant(self: Self, name: [*:0]const u8, value: c_long) !void {
        if (py.c.PyModule_AddIntConstant(self.ptr, name, value) < 0) {
            return root.PyErr.RuntimeError;
        }
    }

    /// Add a string constant to the module
    pub fn addStringConstant(self: Self, name: [*:0]const u8, value: [*:0]const u8) !void {
        if (py.c.PyModule_AddStringConstant(self.ptr, name, value) < 0) {
            return root.PyErr.RuntimeError;
        }
    }

    /// Add a Python object to the module (steals reference)
    pub fn addObject(self: Self, name: [*:0]const u8, value: *py.PyObject) !void {
        if (py.c.PyModule_AddObject(self.ptr, name, value) < 0) {
            return root.PyErr.RuntimeError;
        }
    }

    /// Add a Python object to the module, incrementing refcount first
    pub fn addObjectRef(self: Self, name: [*:0]const u8, value: *py.PyObject) !void {
        py.Py_IncRef(value);
        if (py.c.PyModule_AddObject(self.ptr, name, value) < 0) {
            py.Py_DecRef(value);
            return root.PyErr.RuntimeError;
        }
    }

    /// Get the module's __dict__
    pub fn getDict(self: Self) ?*py.PyObject {
        return py.c.PyModule_GetDict(self.ptr);
    }

    /// Add None to the module under the given name
    pub fn addNone(self: Self, name: [*:0]const u8) !void {
        try self.addObjectRef(name, py.Py_None());
    }

    /// Add True to the module
    pub fn addTrue(self: Self, name: [*:0]const u8) !void {
        try self.addObjectRef(name, py.Py_True());
    }

    /// Add False to the module
    pub fn addFalse(self: Self, name: [*:0]const u8) !void {
        try self.addObjectRef(name, py.Py_False());
    }

    /// Create a submodule and add it to this module
    /// The submodule will be accessible as parent.name
    pub fn createSubmodule(self: Self, comptime name: [*:0]const u8, comptime doc: ?[*:0]const u8, methods: ?[*]py.PyMethodDef) !Module {
        // Create the submodule definition
        const sub_def = comptime createModuleDef(name, doc, null);
        var sub_def_mut = sub_def;
        sub_def_mut.m_methods = methods;

        // Create the submodule
        const submodule = py.PyModule_Create(&sub_def_mut) orelse {
            return root.PyErr.RuntimeError;
        };

        // Add it to the parent module
        try self.addObjectRef(name, submodule);

        return .{ .ptr = submodule };
    }

    /// Add an existing module as a submodule
    pub fn addSubmodule(self: Self, name: [*:0]const u8, submodule: Module) !void {
        try self.addObjectRef(name, submodule.ptr);
    }
};

/// Helper to create a module definition at comptime
pub fn createModuleDef(
    comptime name: [*:0]const u8,
    comptime doc: ?[*:0]const u8,
    methods: ?[*]py.PyMethodDef,
) py.PyModuleDef {
    return .{
        .m_base = py.PyModuleDef_HEAD_INIT,
        .m_name = name,
        .m_doc = doc,
        .m_size = -1, // -1 means the module does not support sub-interpreters
        .m_methods = methods,
        .m_slots = null,
        .m_traverse = null,
        .m_clear = null,
        .m_free = null,
    };
}

/// Create a Python IntEnum class from a Zig enum type
/// Returns the enum class object (new reference) or null on error
pub fn createEnum(comptime E: type, comptime name: [*:0]const u8) ?*py.PyObject {
    const enum_info = @typeInfo(E).@"enum";
    const fields = enum_info.fields;

    // Import the enum module
    const enum_module = py.c.PyImport_ImportModule("enum") orelse return null;
    defer py.Py_DecRef(enum_module);

    // Get IntEnum class
    const int_enum = py.c.PyObject_GetAttrString(enum_module, "IntEnum") orelse return null;
    defer py.Py_DecRef(int_enum);

    // Create a dict for the enum members
    const members_dict = py.c.PyDict_New() orelse return null;
    defer py.Py_DecRef(members_dict);

    // Add each enum field
    inline for (fields) |field| {
        const value: c_long = @intCast(@intFromEnum(@as(E, @enumFromInt(field.value))));
        const py_value = py.c.PyLong_FromLong(value) orelse return null;
        if (py.c.PyDict_SetItemString(members_dict, field.name.ptr, py_value) < 0) {
            py.Py_DecRef(py_value);
            return null;
        }
        py.Py_DecRef(py_value);
    }

    // Create the enum class by calling IntEnum(name, members_dict)
    const name_obj = py.c.PyUnicode_FromString(name) orelse return null;
    defer py.Py_DecRef(name_obj);

    // IntEnum.__call__(name, members) - use functional API
    const args = py.c.PyTuple_Pack(2, name_obj, members_dict) orelse return null;
    defer py.Py_DecRef(args);

    const enum_class = py.c.PyObject_Call(int_enum, args, null);
    return enum_class;
}

/// Create a Python StrEnum class from a Zig enum type
/// The enum field names become the string values
/// Returns the enum class object (new reference) or null on error
pub fn createStrEnum(comptime E: type, comptime name: [*:0]const u8) ?*py.PyObject {
    const enum_info = @typeInfo(E).@"enum";
    const fields = enum_info.fields;

    // Import the enum module
    const enum_module = py.c.PyImport_ImportModule("enum") orelse return null;
    defer py.Py_DecRef(enum_module);

    // Get StrEnum class (Python 3.11+) or fall back to creating a string-valued Enum
    const str_enum = py.c.PyObject_GetAttrString(enum_module, "StrEnum") orelse blk: {
        // StrEnum not available (Python < 3.11), use regular Enum with string values
        py.c.PyErr_Clear();
        break :blk py.c.PyObject_GetAttrString(enum_module, "Enum") orelse return null;
    };
    defer py.Py_DecRef(str_enum);

    // Create a dict for the enum members
    const members_dict = py.c.PyDict_New() orelse return null;
    defer py.Py_DecRef(members_dict);

    // Add each enum field with its name as the string value
    inline for (fields) |field| {
        const py_value = py.c.PyUnicode_FromString(field.name.ptr) orelse return null;
        if (py.c.PyDict_SetItemString(members_dict, field.name.ptr, py_value) < 0) {
            py.Py_DecRef(py_value);
            return null;
        }
        py.Py_DecRef(py_value);
    }

    // Create the enum class by calling StrEnum(name, members_dict)
    const name_obj = py.c.PyUnicode_FromString(name) orelse return null;
    defer py.Py_DecRef(name_obj);

    const args = py.c.PyTuple_Pack(2, name_obj, members_dict) orelse return null;
    defer py.Py_DecRef(args);

    const enum_class = py.c.PyObject_Call(str_enum, args, null);
    return enum_class;
}
