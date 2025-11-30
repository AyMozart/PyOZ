//! Class wrapper for PyOZ
//!
//! This module provides comptime generation of Python classes from Zig structs.
//! It automatically:
//! - Generates __init__ from struct fields
//! - Creates getters/setters for each field
//! - Wraps pub fn methods as Python methods
//!
//! The implementation is split across multiple files in the class/ directory:
//! - mod.zig: Main orchestrator that combines all protocols
//! - wrapper.zig: PyWrapper struct builder
//! - lifecycle.zig: Object lifecycle (py_new, py_init, py_dealloc)
//! - number.zig: Number protocol (__add__, __sub__, etc.)
//! - sequence.zig: Sequence protocol (__len__, __getitem__, etc.)
//! - mapping.zig: Mapping protocol for dict-like access
//! - comparison.zig: Rich comparison (__eq__, __lt__, etc.)
//! - repr.zig: String representation (__repr__, __str__, __hash__)
//! - iterator.zig: Iterator protocol (__iter__, __next__)
//! - buffer.zig: Buffer protocol for numpy compatibility
//! - descriptor.zig: Descriptor protocol (__get__, __set__, __delete__)
//! - attributes.zig: Attribute access (__getattr__, __setattr__)
//! - callable.zig: Callable protocol (__call__)
//! - properties.zig: Property generation (getters/setters)
//! - methods.zig: Method wrappers (instance, static, class)
//! - gc.zig: Garbage collection support (__traverse__, __clear__)

const class_mod = @import("class/mod.zig");
const spec_mod = @import("class/spec.zig");

// Re-export public API
pub const ClassDef = class_mod.ClassDef;
pub const class = class_mod.class;
pub const getWrapper = class_mod.getWrapper;
pub const unwrap = class_mod.unwrap;
pub const createSlotsTuple = class_mod.createSlotsTuple;
pub const addClassAttributes = class_mod.addClassAttributes;
pub const addClassAttributesAbi3 = class_mod.addClassAttributesAbi3;

// ABI3 type creation via PyType_FromSpec
pub const TypeSpec = spec_mod.TypeSpec;
pub const SlotBuilder = spec_mod.SlotBuilder;
pub const buildSlots = spec_mod.buildSlots;
pub const buildSpec = spec_mod.buildSpec;
pub const createType = spec_mod.createType;
pub const createTypeWithBases = spec_mod.createTypeWithBases;
pub const RuntimeSlotBuilder = spec_mod.RuntimeSlotBuilder;
