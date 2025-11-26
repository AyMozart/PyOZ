//! Python Embedding API operations

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const dict = @import("dict.zig");
const PyDict_SetItemString = dict.PyDict_SetItemString;
const PyDict_GetItemString = dict.PyDict_GetItemString;

// ============================================================================
// Python Embedding API
// ============================================================================

/// Input modes for PyRun_String
pub const Py_single_input = c.Py_single_input; // Single interactive statement
pub const Py_file_input = c.Py_file_input; // Module/file (sequence of statements)
pub const Py_eval_input = c.Py_eval_input; // Single expression

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
    return c.PyRun_SimpleStringFlags(code, null);
}

/// Run a string of Python code with globals and locals dicts
/// mode: Py_eval_input (expression), Py_file_input (statements), or Py_single_input (interactive)
/// Returns the result object or null on error
pub fn PyRun_String(code: [*:0]const u8, mode: c_int, globals: *PyObject, locals: *PyObject) ?*PyObject {
    return c.PyRun_StringFlags(code, mode, globals, locals, null);
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
