//! Python Embedding API operations
//!
//! In ABI3 mode, PyRun_* functions are emulated using builtins.exec/eval/compile.

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const dict = @import("dict.zig");
const PyDict_SetItemString = dict.PyDict_SetItemString;
const PyDict_GetItemString = dict.PyDict_GetItemString;
const refcount = @import("refcount.zig");

const abi3_enabled = types.abi3_enabled;

// ============================================================================
// Python Embedding API
// ============================================================================

/// Input modes for PyRun_String
/// In ABI3 mode, these are string constants for compile()
pub const Py_single_input: if (abi3_enabled) []const u8 else c_int =
    if (abi3_enabled) "single" else c.Py_single_input;
pub const Py_file_input: if (abi3_enabled) []const u8 else c_int =
    if (abi3_enabled) "exec" else c.Py_file_input;
pub const Py_eval_input: if (abi3_enabled) []const u8 else c_int =
    if (abi3_enabled) "eval" else c.Py_eval_input;

// ABI3 mode: cache builtins for exec/eval/compile
var builtins_module: ?*PyObject = null;
var exec_func: ?*PyObject = null;
var eval_func: ?*PyObject = null;
var compile_func: ?*PyObject = null;

fn ensureBuiltins() bool {
    if (builtins_module != null) return true;

    builtins_module = c.PyImport_ImportModule("builtins");
    if (builtins_module == null) return false;

    exec_func = c.PyObject_GetAttrString(builtins_module, "exec");
    eval_func = c.PyObject_GetAttrString(builtins_module, "eval");
    compile_func = c.PyObject_GetAttrString(builtins_module, "compile");

    return exec_func != null and eval_func != null and compile_func != null;
}

/// Initialize the Python interpreter
/// Must be called before any other Python API functions
pub fn Py_Initialize() void {
    c.Py_Initialize();
}

/// Initialize the Python interpreter with options
/// If initsigs is 0, skips signal handler registration
pub fn Py_InitializeEx(initsigs: c_int) void {
    c.Py_InitializeEx(initsigs);
}

/// Check if Python is initialized
pub fn Py_IsInitialized() bool {
    return c.Py_IsInitialized() != 0;
}

/// Finalize the Python interpreter
/// Frees all memory allocated by Python
pub fn Py_Finalize() void {
    c.Py_Finalize();
}

/// Finalize with error code
/// Returns 0 on success, -1 if an error occurred
pub fn Py_FinalizeEx() c_int {
    return c.Py_FinalizeEx();
}

/// Run a simple string of Python code
/// Returns 0 on success, -1 on error (exception is printed)
pub fn PyRun_SimpleString(code: [*:0]const u8) c_int {
    if (abi3_enabled) {
        // ABI3: use builtins.exec(code)
        if (!ensureBuiltins()) return -1;

        const code_obj = c.PyUnicode_FromString(code) orelse return -1;
        defer refcount.Py_DecRef(code_obj);

        const args = c.PyTuple_Pack(1, code_obj) orelse return -1;
        defer refcount.Py_DecRef(args);

        const result = c.PyObject_Call(exec_func, args, null);
        if (result == null) {
            c.PyErr_Print();
            return -1;
        }
        refcount.Py_DecRef(result);
        return 0;
    } else {
        return c.PyRun_SimpleStringFlags(code, null);
    }
}

/// Run a string of Python code with globals and locals dicts
/// mode: Py_eval_input (expression), Py_file_input (statements), or Py_single_input (interactive)
/// Returns the result object or null on error
pub fn PyRun_String(code: [*:0]const u8, mode: anytype, globals: *PyObject, locals: *PyObject) ?*PyObject {
    if (abi3_enabled) {
        // ABI3: use compile() + exec()/eval()
        if (!ensureBuiltins()) return null;

        const code_obj = c.PyUnicode_FromString(code) orelse return null;
        defer refcount.Py_DecRef(code_obj);

        // mode is a string in ABI3 mode ("eval", "exec", or "single")
        const mode_str: []const u8 = mode;
        const mode_obj = c.PyUnicode_FromStringAndSize(mode_str.ptr, @intCast(mode_str.len)) orelse return null;
        defer refcount.Py_DecRef(mode_obj);

        const filename = c.PyUnicode_FromString("<string>") orelse return null;
        defer refcount.Py_DecRef(filename);

        // compile(code, "<string>", mode)
        const compile_args = c.PyTuple_Pack(3, code_obj, filename, mode_obj) orelse return null;
        defer refcount.Py_DecRef(compile_args);

        const compiled = c.PyObject_Call(compile_func, compile_args, null) orelse return null;
        defer refcount.Py_DecRef(compiled);

        // For eval mode, use eval(); otherwise use exec()
        const is_eval = mode_str.len == 4 and mode_str[0] == 'e' and mode_str[1] == 'v';
        const run_func = if (is_eval) eval_func else exec_func;

        // exec/eval(compiled, globals, locals)
        const run_args = c.PyTuple_Pack(3, compiled, globals, locals) orelse return null;
        defer refcount.Py_DecRef(run_args);

        return c.PyObject_Call(run_func, run_args, null);
    } else {
        return c.PyRun_StringFlags(code, mode, globals, locals, null);
    }
}

/// Get the __main__ module
pub fn PyImport_AddModule(name: [*:0]const u8) ?*PyObject {
    return c.PyImport_AddModule(name);
}

/// Import a module by name
pub fn PyImport_ImportModule(name: [*:0]const u8) ?*PyObject {
    return c.PyImport_ImportModule(name);
}

/// Get a global variable from __main__
pub fn PyMain_GetGlobal(name: [*:0]const u8) ?*PyObject {
    const module_ops = @import("module.zig");
    const main_module = PyImport_AddModule("__main__") orelse return null;
    const main_dict = module_ops.PyModule_GetDict(main_module) orelse return null;
    return PyDict_GetItemString(main_dict, name);
}

/// Set a global variable in __main__
pub fn PyMain_SetGlobal(name: [*:0]const u8, value: *PyObject) bool {
    const module_ops = @import("module.zig");
    const main_module = PyImport_AddModule("__main__") orelse return false;
    const main_dict = module_ops.PyModule_GetDict(main_module) orelse return false;
    return PyDict_SetItemString(main_dict, name, value) == 0;
}

/// Evaluate a Python expression and return the result
/// Returns null on error (use PyErr_Occurred to check)
pub fn PyEval_Expression(expr: [*:0]const u8) ?*PyObject {
    const module_ops = @import("module.zig");
    const main_module = PyImport_AddModule("__main__") orelse return null;
    const main_dict = module_ops.PyModule_GetDict(main_module) orelse return null;
    return PyRun_String(expr, Py_eval_input, main_dict, main_dict);
}

/// Execute Python statements
/// Returns true on success, false on error
pub fn PyExec_Statements(code: [*:0]const u8) bool {
    return PyRun_SimpleString(code) == 0;
}
