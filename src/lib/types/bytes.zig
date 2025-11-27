//! Bytes types for Python interop
//!
//! Provides Bytes and ByteArray types for working with Python bytes and bytearray objects.

/// A bytes type for accepting Python bytes
pub const Bytes = struct {
    const _is_pyoz_bytes = true;

    data: []const u8,
};

/// A bytearray type for accepting Python bytearray (mutable)
pub const ByteArray = struct {
    const _is_pyoz_bytearray = true;

    data: []u8,
};
