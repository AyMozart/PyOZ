//! Type Slot Constants for PyType_FromSpec
//!
//! These constants are used with PyType_Spec to define type slots when
//! creating heap types via PyType_FromSpec(). They are part of the Stable ABI
//! (Limited API) and their values are guaranteed not to change.
//!
//! Usage:
//! ```zig
//! const slots = [_]py.PyType_Slot{
//!     .{ .slot = py.slots.tp_init, .pfunc = @ptrCast(&my_init) },
//!     .{ .slot = py.slots.tp_new, .pfunc = @ptrCast(&my_new) },
//!     .{ .slot = 0, .pfunc = null }, // sentinel
//! };
//! ```
//!
//! Note: Buffer protocol slots (Py_bf_getbuffer, Py_bf_releasebuffer) are
//! explicitly disabled in Limited API mode - see typeslots.h.

const types = @import("types.zig");
const c = types.c;

// ============================================================================
// Mapping Protocol Slots (mp_*)
// ============================================================================

/// __len__ for mappings - mp_length
pub const mp_ass_subscript: c_int = c.Py_mp_ass_subscript;
/// __len__ for mappings
pub const mp_length: c_int = c.Py_mp_length;
/// __getitem__ for mappings
pub const mp_subscript: c_int = c.Py_mp_subscript;

// ============================================================================
// Number Protocol Slots (nb_*)
// ============================================================================

/// __abs__
pub const nb_absolute: c_int = c.Py_nb_absolute;
/// __add__
pub const nb_add: c_int = c.Py_nb_add;
/// __and__
pub const nb_and: c_int = c.Py_nb_and;
/// __bool__
pub const nb_bool: c_int = c.Py_nb_bool;
/// __divmod__
pub const nb_divmod: c_int = c.Py_nb_divmod;
/// __float__
pub const nb_float: c_int = c.Py_nb_float;
/// __floordiv__
pub const nb_floor_divide: c_int = c.Py_nb_floor_divide;
/// __index__
pub const nb_index: c_int = c.Py_nb_index;
/// __iadd__
pub const nb_inplace_add: c_int = c.Py_nb_inplace_add;
/// __iand__
pub const nb_inplace_and: c_int = c.Py_nb_inplace_and;
/// __ifloordiv__
pub const nb_inplace_floor_divide: c_int = c.Py_nb_inplace_floor_divide;
/// __ilshift__
pub const nb_inplace_lshift: c_int = c.Py_nb_inplace_lshift;
/// __imul__
pub const nb_inplace_multiply: c_int = c.Py_nb_inplace_multiply;
/// __ior__
pub const nb_inplace_or: c_int = c.Py_nb_inplace_or;
/// __ipow__
pub const nb_inplace_power: c_int = c.Py_nb_inplace_power;
/// __imod__
pub const nb_inplace_remainder: c_int = c.Py_nb_inplace_remainder;
/// __irshift__
pub const nb_inplace_rshift: c_int = c.Py_nb_inplace_rshift;
/// __isub__
pub const nb_inplace_subtract: c_int = c.Py_nb_inplace_subtract;
/// __itruediv__
pub const nb_inplace_true_divide: c_int = c.Py_nb_inplace_true_divide;
/// __ixor__
pub const nb_inplace_xor: c_int = c.Py_nb_inplace_xor;
/// __int__
pub const nb_int: c_int = c.Py_nb_int;
/// __invert__
pub const nb_invert: c_int = c.Py_nb_invert;
/// __lshift__
pub const nb_lshift: c_int = c.Py_nb_lshift;
/// __mul__
pub const nb_multiply: c_int = c.Py_nb_multiply;
/// __neg__
pub const nb_negative: c_int = c.Py_nb_negative;
/// __or__
pub const nb_or: c_int = c.Py_nb_or;
/// __pos__
pub const nb_positive: c_int = c.Py_nb_positive;
/// __pow__
pub const nb_power: c_int = c.Py_nb_power;
/// __mod__
pub const nb_remainder: c_int = c.Py_nb_remainder;
/// __rshift__
pub const nb_rshift: c_int = c.Py_nb_rshift;
/// __sub__
pub const nb_subtract: c_int = c.Py_nb_subtract;
/// __truediv__
pub const nb_true_divide: c_int = c.Py_nb_true_divide;
/// __xor__
pub const nb_xor: c_int = c.Py_nb_xor;
/// __matmul__ (Python 3.5+)
pub const nb_matrix_multiply: c_int = c.Py_nb_matrix_multiply;
/// __imatmul__ (Python 3.5+)
pub const nb_inplace_matrix_multiply: c_int = c.Py_nb_inplace_matrix_multiply;

// ============================================================================
// Sequence Protocol Slots (sq_*)
// ============================================================================

/// __setitem__ / __delitem__ for sequences
pub const sq_ass_item: c_int = c.Py_sq_ass_item;
/// __add__ for sequences (concatenation)
pub const sq_concat: c_int = c.Py_sq_concat;
/// __contains__
pub const sq_contains: c_int = c.Py_sq_contains;
/// __iadd__ for sequences
pub const sq_inplace_concat: c_int = c.Py_sq_inplace_concat;
/// __imul__ for sequences
pub const sq_inplace_repeat: c_int = c.Py_sq_inplace_repeat;
/// __getitem__ for sequences
pub const sq_item: c_int = c.Py_sq_item;
/// __len__ for sequences
pub const sq_length: c_int = c.Py_sq_length;
/// __mul__ for sequences (repeat)
pub const sq_repeat: c_int = c.Py_sq_repeat;

// ============================================================================
// Type Protocol Slots (tp_*)
// ============================================================================

/// tp_alloc - allocation function
pub const tp_alloc: c_int = c.Py_tp_alloc;
/// tp_base - base type
pub const tp_base: c_int = c.Py_tp_base;
/// tp_bases - tuple of base types
pub const tp_bases: c_int = c.Py_tp_bases;
/// __call__
pub const tp_call: c_int = c.Py_tp_call;
/// tp_clear - GC clear function
pub const tp_clear: c_int = c.Py_tp_clear;
/// tp_dealloc - destructor
pub const tp_dealloc: c_int = c.Py_tp_dealloc;
/// __del__ (ensure reference counting is correct when using)
pub const tp_del: c_int = c.Py_tp_del;
/// __get__ (descriptor protocol)
pub const tp_descr_get: c_int = c.Py_tp_descr_get;
/// __set__ / __delete__ (descriptor protocol)
pub const tp_descr_set: c_int = c.Py_tp_descr_set;
/// __doc__
pub const tp_doc: c_int = c.Py_tp_doc;
/// tp_getattr - legacy attribute access (use tp_getattro instead)
pub const tp_getattr: c_int = c.Py_tp_getattr;
/// __getattribute__ / __getattr__
pub const tp_getattro: c_int = c.Py_tp_getattro;
/// __hash__
pub const tp_hash: c_int = c.Py_tp_hash;
/// __init__
pub const tp_init: c_int = c.Py_tp_init;
/// tp_is_gc - GC check function
pub const tp_is_gc: c_int = c.Py_tp_is_gc;
/// __iter__
pub const tp_iter: c_int = c.Py_tp_iter;
/// __next__
pub const tp_iternext: c_int = c.Py_tp_iternext;
/// tp_methods - method definitions
pub const tp_methods: c_int = c.Py_tp_methods;
/// __new__
pub const tp_new: c_int = c.Py_tp_new;
/// __repr__
pub const tp_repr: c_int = c.Py_tp_repr;
/// __eq__, __ne__, __lt__, __le__, __gt__, __ge__
pub const tp_richcompare: c_int = c.Py_tp_richcompare;
/// tp_setattr - legacy attribute access (use tp_setattro instead)
pub const tp_setattr: c_int = c.Py_tp_setattr;
/// __setattr__ / __delattr__
pub const tp_setattro: c_int = c.Py_tp_setattro;
/// __str__
pub const tp_str: c_int = c.Py_tp_str;
/// tp_traverse - GC traversal function
pub const tp_traverse: c_int = c.Py_tp_traverse;
/// tp_members - member definitions
pub const tp_members: c_int = c.Py_tp_members;
/// tp_getset - getset definitions
pub const tp_getset: c_int = c.Py_tp_getset;
/// tp_free - deallocation function
pub const tp_free: c_int = c.Py_tp_free;
/// tp_finalize - PEP 442 destructor (Python 3.5+)
pub const tp_finalize: c_int = c.Py_tp_finalize;

// ============================================================================
// Async Protocol Slots (am_*) - Python 3.5+
// ============================================================================

/// __await__
pub const am_await: c_int = c.Py_am_await;
/// __aiter__
pub const am_aiter: c_int = c.Py_am_aiter;
/// __anext__
pub const am_anext: c_int = c.Py_am_anext;

// am_send was added in Python 3.10
// We check if it exists in the C headers before exposing it
pub const am_send: c_int = if (@hasDecl(c, "Py_am_send")) c.Py_am_send else 81;

// ============================================================================
// Buffer Protocol Slots (bf_*) - NOT available in Limited API!
// ============================================================================

// Note: These are explicitly #undef'd in typeslots.h when Py_LIMITED_API is defined.
// They are included here for non-ABI3 builds only.

/// Check if buffer slots are available (only in non-Limited API builds)
pub const has_buffer_slots = @hasDecl(c, "Py_bf_getbuffer");

/// __buffer__ - get buffer (NOT in Limited API)
pub const bf_getbuffer: c_int = if (has_buffer_slots) c.Py_bf_getbuffer else 0;
/// Release buffer (NOT in Limited API)
pub const bf_releasebuffer: c_int = if (has_buffer_slots) c.Py_bf_releasebuffer else 0;
