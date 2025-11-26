//! GIL (Global Interpreter Lock) operations for Python C API

const types = @import("types.zig");
const c = types.c;

// ============================================================================
// GIL (Global Interpreter Lock) control
// ============================================================================

// Note: We define PyThreadState as opaque and use extern declarations to avoid
// cImport issues with Python 3.12+ where the struct contains anonymous structs
// that Zig's cImport cannot translate.
pub const PyThreadState = opaque {};
pub const PyGILState_STATE = c_uint;

// Extern declarations for GIL functions - avoids cImport resolving PyThreadState struct
pub extern fn PyEval_SaveThread() ?*PyThreadState;
pub extern fn PyEval_RestoreThread(state: ?*PyThreadState) void;
pub extern fn PyGILState_Ensure() PyGILState_STATE;
pub extern fn PyGILState_Release(state: PyGILState_STATE) void;
