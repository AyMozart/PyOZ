//! Buffer protocol for class generation
//!
//! Implements __buffer__ for buffer protocol support

const std = @import("std");
const py = @import("../python.zig");

/// Build buffer protocol for a given type
pub fn BufferProtocol(comptime T: type, comptime Parent: type) type {
    return struct {
        pub fn hasBufferProtocol() bool {
            return @hasDecl(T, "__buffer__");
        }

        pub var buffer_procs: py.PyBufferProcs = makeBufferProcs();

        fn makeBufferProcs() py.PyBufferProcs {
            var bp: py.PyBufferProcs = std.mem.zeroes(py.PyBufferProcs);
            bp.bf_getbuffer = @ptrCast(&py_bf_getbuffer);
            bp.bf_releasebuffer = @ptrCast(&py_bf_releasebuffer);
            return bp;
        }

        fn py_bf_getbuffer(self_obj: ?*py.PyObject, view: ?*py.Py_buffer, flags: c_int) callconv(.c) c_int {
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
