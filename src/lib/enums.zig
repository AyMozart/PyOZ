//! Enum Support
//!
//! Provides types for exposing Zig enums as Python IntEnum and StrEnum.

/// Enum definition for the module (IntEnum)
pub const EnumDef = struct {
    /// Name of the enum in Python (e.g., "Color")
    name: [*:0]const u8,
    /// The Zig enum type
    zig_type: type,
};

/// Create an enum definition from a Zig enum type (IntEnum)
pub fn enumDef(comptime name: [*:0]const u8, comptime E: type) EnumDef {
    return .{
        .name = name,
        .zig_type = E,
    };
}

/// String enum definition for the module (StrEnum)
pub const StrEnumDef = struct {
    /// Name of the enum in Python (e.g., "Status")
    name: [*:0]const u8,
    /// The Zig enum type
    zig_type: type,
};

/// Create a string enum definition from a Zig enum type (StrEnum)
/// The enum field names become the string values
pub fn strEnumDef(comptime name: [*:0]const u8, comptime E: type) StrEnumDef {
    return .{
        .name = name,
        .zig_type = E,
    };
}
