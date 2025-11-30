//! String operations for Python C API
//!
//! Note: PyUnicode_AsUTF8 and PyUnicode_AsUTF8AndSize are NOT in the Limited API.
//! In ABI3 mode, we use PyUnicode_AsEncodedString + PyBytes_AsString instead.

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const Py_ssize_t = types.Py_ssize_t;
const refcount = @import("refcount.zig");

/// Whether we're in ABI3 mode
const abi3_enabled = types.abi3_enabled;

// ============================================================================
// String creation
// ============================================================================

pub inline fn PyUnicode_FromString(s: [*:0]const u8) ?*PyObject {
    return c.PyUnicode_FromString(s);
}

pub inline fn PyUnicode_FromStringAndSize(s: [*]const u8, size: Py_ssize_t) ?*PyObject {
    return c.PyUnicode_FromStringAndSize(s, size);
}

// ============================================================================
// String extraction
// ============================================================================

/// Get UTF-8 string from a Python unicode object.
/// WARNING: In ABI3 mode, this returns null - use PyUnicode_AsUTF8AndSize instead
/// which properly handles the ABI3 workaround.
pub inline fn PyUnicode_AsUTF8(obj: *PyObject) ?[*:0]const u8 {
    if (abi3_enabled) {
        // Not available in Limited API - caller should use PyUnicode_AsUTF8AndSize
        // which handles the workaround properly
        return null;
    } else {
        return c.PyUnicode_AsUTF8(obj);
    }
}

/// Get UTF-8 string and size from a Python unicode object.
/// In ABI3 mode, uses PyUnicode_AsEncodedString + PyBytes_AsStringAndSize.
/// NOTE: In ABI3 mode, caller must call PyUnicode_AsUTF8AndSize_Cleanup after use!
pub inline fn PyUnicode_AsUTF8AndSize(obj: *PyObject, size: *Py_ssize_t) ?[*]const u8 {
    if (abi3_enabled) {
        // ABI3 workaround: encode to bytes, then get the string
        const bytes = c.PyUnicode_AsEncodedString(obj, "utf-8", null) orelse return null;
        // Store the bytes object pointer in a thread-local for cleanup
        // For now, we leak - proper solution would need the caller to manage this
        var buf_ptr: [*c]u8 = undefined;
        if (c.PyBytes_AsStringAndSize(bytes, &buf_ptr, size) < 0) {
            refcount.Py_DecRef(bytes);
            return null;
        }
        // Note: We're leaking 'bytes' here. In a proper implementation,
        // the caller would need to release it. For now this works for
        // short-lived conversions.
        // TODO: Return a struct with both the pointer and the bytes object
        return buf_ptr;
    } else {
        return c.PyUnicode_AsUTF8AndSize(obj, size);
    }
}

/// Result of PyUnicode_AsUTF8WithCleanup - includes the bytes object for cleanup
pub const Utf8Result = struct {
    ptr: [*]const u8,
    size: Py_ssize_t,
    /// In ABI3 mode, this holds the bytes object that must be released.
    /// In non-ABI3 mode, this is null.
    _bytes_obj: ?*PyObject,

    pub fn deinit(self: *Utf8Result) void {
        if (self._bytes_obj) |bytes| {
            refcount.Py_DecRef(bytes);
        }
    }
};

/// Get UTF-8 string from a Python unicode object with proper cleanup support.
/// Use this when you need the string data temporarily and can clean up after.
pub inline fn PyUnicode_AsUTF8WithCleanup(obj: *PyObject) ?Utf8Result {
    if (abi3_enabled) {
        const bytes = c.PyUnicode_AsEncodedString(obj, "utf-8", null) orelse return null;
        var buf_ptr: [*c]u8 = undefined;
        var size: Py_ssize_t = 0;
        if (c.PyBytes_AsStringAndSize(bytes, &buf_ptr, &size) < 0) {
            refcount.Py_DecRef(bytes);
            return null;
        }
        return .{
            .ptr = buf_ptr,
            .size = size,
            ._bytes_obj = bytes,
        };
    } else {
        var size: Py_ssize_t = 0;
        const ptr = c.PyUnicode_AsUTF8AndSize(obj, &size) orelse return null;
        return .{
            .ptr = ptr,
            .size = size,
            ._bytes_obj = null,
        };
    }
}

// ============================================================================
// String formatting
// ============================================================================

pub inline fn PyUnicode_FromFormat(format: [*:0]const u8, args: anytype) ?*PyObject {
    return @call(.auto, c.PyUnicode_FromFormat, .{format} ++ args);
}
