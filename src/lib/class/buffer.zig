//! Buffer protocol for class generation
//!
//! Implements __buffer__ for buffer protocol support
//!
//! NOTE: The buffer protocol producer (__buffer__) is NOT part of the Python Stable ABI.
//! Using __buffer__ in your class will cause a compile error in ABI3 mode.

const std = @import("std");
const py = @import("../python.zig");

const abi3_enabled = py.types.abi3_enabled;

const abi3_error_msg =
    \\The buffer protocol producer (__buffer__) is NOT part of the Python Stable ABI.
    \\
    \\You cannot implement __buffer__ on classes in ABI3 mode because:
    \\  - Py_buffer struct layout is not exposed in the Limited API
    \\  - PyBufferProcs is not available
    \\  - bf_getbuffer/bf_releasebuffer slots don't exist
    \\
    \\Workarounds:
    \\  - Return a bytes object from a regular method instead
    \\  - Use a list to return data
    \\  - Set abi3 = false in your build configuration
    \\
    \\Note: BufferView (buffer consumer) IS available in ABI3 mode for reading
    \\numpy arrays, but with a performance cost (data is copied).
;

/// Build buffer protocol for a given type
pub fn BufferProtocol(comptime T: type, comptime Parent: type) type {
    // ABI3 guard: buffer protocol producer is not available
    if (abi3_enabled and @hasDecl(T, "__buffer__")) {
        @compileError(abi3_error_msg);
    }

    return struct {
        pub fn hasBufferProtocol() bool {
            return @hasDecl(T, "__buffer__");
        }

        pub var buffer_procs: py.PyBufferProcs = if (!abi3_enabled) makeBufferProcs() else undefined;

        fn makeBufferProcs() py.PyBufferProcs {
            if (abi3_enabled) {
                // This branch is unreachable due to compile error above
                unreachable;
            }
            var bp: py.PyBufferProcs = std.mem.zeroes(py.PyBufferProcs);
            bp.bf_getbuffer = @ptrCast(&py_bf_getbuffer);
            bp.bf_releasebuffer = @ptrCast(&py_bf_releasebuffer);
            return bp;
        }

        fn py_bf_getbuffer(self_obj: ?*py.PyObject, view: ?*py.Py_buffer, flags: c_int) callconv(.c) c_int {
            if (abi3_enabled) unreachable;

            const self: *Parent.PyWrapper = @ptrCast(@alignCast(self_obj orelse return -1));
            const v = view orelse return -1;

            const info = T.__buffer__(self.getData());

            v.buf = @ptrCast(info.ptr);
            v.obj = self_obj;
            py.Py_IncRef(self_obj);
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
        }
    };
}
