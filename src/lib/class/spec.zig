//! PyType_FromSpec builder for ABI3 mode
//!
//! This module provides comptime generation of PyType_Spec and slot arrays
//! for creating heap types via PyType_FromSpec() in ABI3 (Limited API) mode.
//!
//! In non-ABI3 mode, we use static PyTypeObject directly.
//! In ABI3 mode, we must use PyType_FromSpec with slot arrays.

const std = @import("std");
const py = @import("../python.zig");
const slots = py.slots;

const abi3_enabled = py.types.abi3_enabled;

/// Maximum number of slots we can have (generous upper bound)
const MAX_SLOTS = 64;

/// A slot entry for PyType_Spec
pub const Slot = py.PyType_Slot;

/// Build a PyType_Spec for creating a heap type
pub fn TypeSpec(comptime name: [*:0]const u8, comptime basicsize: isize, comptime flags: c_ulong) type {
    return struct {
        const Self = @This();

        /// The spec structure
        spec: py.PyType_Spec,

        /// Storage for slots (must be static for pointer stability)
        slot_storage: [MAX_SLOTS]Slot,
        slot_count: usize,

        /// Initialize a new TypeSpec builder
        pub fn init() Self {
            return .{
                .spec = .{
                    .name = name,
                    .basicsize = @intCast(basicsize),
                    .itemsize = 0,
                    .flags = flags,
                    .slots = undefined, // Will be set when finalized
                },
                .slot_storage = std.mem.zeroes([MAX_SLOTS]Slot),
                .slot_count = 0,
            };
        }

        /// Add a slot to the spec
        pub fn addSlot(self: *Self, slot_id: c_int, func: ?*anyopaque) void {
            if (self.slot_count >= MAX_SLOTS - 1) {
                @panic("Too many slots in TypeSpec");
            }
            self.slot_storage[self.slot_count] = .{
                .slot = slot_id,
                .pfunc = func,
            };
            self.slot_count += 1;
        }

        /// Finalize the spec (adds sentinel and returns pointer to spec)
        pub fn finalize(self: *Self) *py.PyType_Spec {
            // Add sentinel
            self.slot_storage[self.slot_count] = .{
                .slot = 0,
                .pfunc = null,
            };
            // Point spec.slots to our storage
            self.spec.slots = &self.slot_storage;
            return &self.spec;
        }
    };
}

/// Helper to build slot array at comptime
pub fn SlotBuilder(comptime max_slots: usize) type {
    return struct {
        const Self = @This();

        slots: [max_slots]Slot,
        count: usize,

        pub fn init() Self {
            return .{
                .slots = std.mem.zeroes([max_slots]Slot),
                .count = 0,
            };
        }

        pub fn add(self: *Self, slot_id: c_int, func: ?*anyopaque) void {
            self.slots[self.count] = .{
                .slot = slot_id,
                .pfunc = func,
            };
            self.count += 1;
        }

        pub fn addSentinel(self: *Self) void {
            self.slots[self.count] = .{
                .slot = 0,
                .pfunc = null,
            };
        }

        pub fn getSlots(self: *const Self) []const Slot {
            return self.slots[0 .. self.count + 1]; // +1 for sentinel
        }
    };
}

/// Create a type using PyType_FromSpec
/// Returns null if type creation fails
pub fn createType(spec: *py.PyType_Spec) ?*py.PyTypeObject {
    const type_obj = py.c.PyType_FromSpec(spec);
    if (type_obj == null) return null;
    return @ptrCast(type_obj);
}

/// Create a type with bases using PyType_FromSpecWithBases
pub fn createTypeWithBases(spec: *py.PyType_Spec, bases: ?*py.PyObject) ?*py.PyTypeObject {
    const type_obj = py.c.PyType_FromSpecWithBases(spec, bases);
    if (type_obj == null) return null;
    return @ptrCast(type_obj);
}

// ============================================================================
// Comptime Slot Array Builder
// ============================================================================

/// Build a static slot array at comptime
/// Usage:
/// ```zig
/// const my_slots = comptime buildSlots(.{
///     .{ slots.tp_init, @ptrCast(&my_init) },
///     .{ slots.tp_new, @ptrCast(&my_new) },
///     .{ slots.tp_dealloc, @ptrCast(&my_dealloc) },
/// });
/// ```
pub fn buildSlots(comptime slot_defs: anytype) [slot_defs.len + 1]Slot {
    var result: [slot_defs.len + 1]Slot = undefined;

    inline for (slot_defs, 0..) |def, i| {
        result[i] = .{
            .slot = def[0],
            .pfunc = def[1],
        };
    }

    // Sentinel
    result[slot_defs.len] = .{
        .slot = 0,
        .pfunc = null,
    };

    return result;
}

/// Build a PyType_Spec at comptime
pub fn buildSpec(
    comptime name: [*:0]const u8,
    comptime basicsize: c_int,
    comptime flags: c_uint,
    comptime slot_array: []const Slot,
) py.PyType_Spec {
    return .{
        .name = name,
        .basicsize = basicsize,
        .itemsize = 0,
        .flags = flags,
        .slots = @ptrCast(slot_array.ptr),
    };
}

// ============================================================================
// Runtime Slot Builder (for dynamic slot arrays)
// ============================================================================

/// A runtime slot builder that can add slots dynamically
pub const RuntimeSlotBuilder = struct {
    slots: []Slot,
    count: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, max_slots: usize) !RuntimeSlotBuilder {
        const slot_mem = try allocator.alloc(Slot, max_slots);
        return .{
            .slots = slot_mem,
            .count = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RuntimeSlotBuilder) void {
        self.allocator.free(self.slots);
    }

    pub fn add(self: *RuntimeSlotBuilder, slot_id: c_int, func: ?*anyopaque) void {
        if (self.count >= self.slots.len - 1) return;
        self.slots[self.count] = .{
            .slot = slot_id,
            .pfunc = func,
        };
        self.count += 1;
    }

    pub fn finalize(self: *RuntimeSlotBuilder) []Slot {
        // Add sentinel
        self.slots[self.count] = .{
            .slot = 0,
            .pfunc = null,
        };
        return self.slots[0 .. self.count + 1];
    }
};

// ============================================================================
// Tests
// ============================================================================

test "buildSlots creates correct slot array" {
    const test_slots = comptime buildSlots(.{
        .{ slots.tp_init, @as(?*anyopaque, null) },
        .{ slots.tp_new, @as(?*anyopaque, null) },
    });

    try std.testing.expectEqual(@as(usize, 3), test_slots.len);
    try std.testing.expectEqual(slots.tp_init, test_slots[0].slot);
    try std.testing.expectEqual(slots.tp_new, test_slots[1].slot);
    try std.testing.expectEqual(@as(c_int, 0), test_slots[2].slot); // sentinel
}
