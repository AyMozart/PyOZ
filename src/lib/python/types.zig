//! Core Python C API types
//!
//! Re-exports essential types from the Python C API.
//! When ABI3 mode is enabled, defines Py_LIMITED_API to restrict to Stable ABI.

const std = @import("std");
const build_options = @import("build_options");

// ABI3 configuration - hardcoded to Python 3.8 minimum
pub const abi3_enabled = build_options.abi3;
pub const abi3_version = "3.8";
pub const abi3_version_hex = 0x03080000;

// Import Python C API from system headers
// In ABI3 mode, we define Py_LIMITED_API and exclude non-stable headers
pub const c = @cImport({
    @cDefine("PY_SSIZE_T_CLEAN", "1");

    // Define Py_LIMITED_API for Python 3.8 minimum
    if (abi3_enabled) {
        @cDefine("Py_LIMITED_API", "0x03080000");
    }

    @cInclude("Python.h");

    // datetime.h and structmember.h are NOT part of the Stable ABI
    if (!abi3_enabled) {
        @cInclude("datetime.h");
        @cInclude("structmember.h");
    }
});

// ============================================================================
// Re-export essential types
// ============================================================================

pub const PyObject = c.PyObject;
pub const Py_ssize_t = c.Py_ssize_t;
pub const PyTypeObject = c.PyTypeObject;

// Method definition
pub const PyMethodDef = c.PyMethodDef;
pub const PyCFunction = *const fn (?*PyObject, ?*PyObject) callconv(.c) ?*PyObject;

// Member/GetSet definitions for class attributes
pub const PyMemberDef = c.PyMemberDef;
pub const PyGetSetDef = c.PyGetSetDef;
pub const getter = *const fn (?*PyObject, ?*anyopaque) callconv(.c) ?*PyObject;
pub const setter = *const fn (?*PyObject, ?*PyObject, ?*anyopaque) callconv(.c) c_int;

// Type slots for heap types
pub const PyType_Slot = c.PyType_Slot;
pub const PyType_Spec = c.PyType_Spec;

// Module definition
pub const PyModuleDef = c.PyModuleDef;
pub const PyModuleDef_Base = c.PyModuleDef_Base;

// Python 3.12+ uses an anonymous union for ob_refcnt (PEP 683 immortal objects)
// We detect this at comptime and handle both cases
pub const has_direct_ob_refcnt = @hasField(c.PyObject, "ob_refcnt");

pub const PyModuleDef_HEAD_INIT: PyModuleDef_Base = blk: {
    var base: PyModuleDef_Base = std.mem.zeroes(PyModuleDef_Base);
    base.m_init = null;
    base.m_index = 0;
    base.m_copy = null;
    // Set ob_refcnt based on Python version struct layout
    if (has_direct_ob_refcnt) {
        base.ob_base.ob_refcnt = 1;
    } else {
        // Python 3.12+: ob_refcnt is inside anonymous union, access via pointer
        const ob_ptr: *Py_ssize_t = @ptrCast(&base.ob_base);
        ob_ptr.* = 1;
    }
    base.ob_base.ob_type = null;
    break :blk base;
};

// Method flags
pub const METH_VARARGS: c_int = c.METH_VARARGS;
pub const METH_KEYWORDS: c_int = c.METH_KEYWORDS;
pub const METH_NOARGS: c_int = c.METH_NOARGS;
pub const METH_O: c_int = c.METH_O;
pub const METH_STATIC: c_int = c.METH_STATIC;
pub const METH_CLASS: c_int = c.METH_CLASS;

// Type flags
pub const Py_TPFLAGS_DEFAULT: c_ulong = c.Py_TPFLAGS_DEFAULT;
pub const Py_TPFLAGS_HAVE_GC: c_ulong = c.Py_TPFLAGS_HAVE_GC;
pub const Py_TPFLAGS_BASETYPE: c_ulong = c.Py_TPFLAGS_BASETYPE;
pub const Py_TPFLAGS_HEAPTYPE: c_ulong = c.Py_TPFLAGS_HEAPTYPE;

// Sequence and Mapping protocols
pub const PySequenceMethods = c.PySequenceMethods;
pub const PyMappingMethods = c.PyMappingMethods;

// Type slots
pub const Py_tp_init: c_int = c.Py_tp_init;
pub const Py_tp_new: c_int = c.Py_tp_new;
pub const Py_tp_dealloc: c_int = c.Py_tp_dealloc;
pub const Py_tp_methods: c_int = c.Py_tp_methods;
pub const Py_tp_members: c_int = c.Py_tp_members;
pub const Py_tp_getset: c_int = c.Py_tp_getset;
pub const Py_tp_doc: c_int = c.Py_tp_doc;
pub const Py_tp_repr: c_int = c.Py_tp_repr;
pub const Py_tp_str: c_int = c.Py_tp_str;
