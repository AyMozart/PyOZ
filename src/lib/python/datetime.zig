//! DateTime API operations for Python C API

const types = @import("types.zig");
const c = types.c;
const PyObject = types.PyObject;
const PyTypeObject = types.PyTypeObject;
const typecheck = @import("typecheck.zig");
const Py_TYPE = typecheck.Py_TYPE;

// ============================================================================
// DateTime API
// ============================================================================

/// The datetime CAPI - lazily initialized on first use
var datetime_api: ?*c.PyDateTime_CAPI = null;

/// Ensure datetime API is initialized (called automatically by datetime functions)
fn ensureDateTimeAPI() ?*c.PyDateTime_CAPI {
    if (datetime_api) |api| return api;
    datetime_api = @ptrCast(@alignCast(c.PyCapsule_Import("datetime.datetime_CAPI", 0)));
    return datetime_api;
}

/// Explicitly initialize the datetime API (optional - happens automatically on first use)
pub fn PyDateTime_Import() bool {
    return ensureDateTimeAPI() != null;
}

/// Check if datetime API is initialized
pub fn PyDateTime_IsInitialized() bool {
    return datetime_api != null;
}

/// Create a date object
pub fn PyDate_FromDate(year: c_int, month: c_int, day: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.Date_FromDate orelse return null;
    return func(year, month, day, api.DateType);
}

/// Create a datetime object
pub fn PyDateTime_FromDateAndTime(year: c_int, month: c_int, day: c_int, hour: c_int, minute: c_int, second: c_int, usecond: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.DateTime_FromDateAndTime orelse return null;
    return func(year, month, day, hour, minute, second, usecond, @ptrCast(&c._Py_NoneStruct), api.DateTimeType);
}

/// Create a time object
pub fn PyTime_FromTime(hour: c_int, minute: c_int, second: c_int, usecond: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.Time_FromTime orelse return null;
    return func(hour, minute, second, usecond, @ptrCast(&c._Py_NoneStruct), api.TimeType);
}

/// Create a timedelta object
pub fn PyDelta_FromDSU(days: c_int, seconds: c_int, useconds: c_int) ?*PyObject {
    const api = ensureDateTimeAPI() orelse return null;
    const func = api.Delta_FromDelta orelse return null;
    return func(days, seconds, useconds, 1, api.DeltaType);
}

/// Check if object is a date (or datetime)
pub fn PyDate_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DateType)) != 0;
}

/// Check if object is a datetime
pub fn PyDateTime_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DateTimeType)) != 0;
}

/// Check if object is a time
pub fn PyTime_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.TimeType)) != 0;
}

/// Check if object is a timedelta
pub fn PyDelta_Check(obj: *PyObject) bool {
    const api = ensureDateTimeAPI() orelse return false;
    return c.PyType_IsSubtype(Py_TYPE(obj), @ptrCast(api.DeltaType)) != 0;
}

/// Get year from date/datetime
pub fn PyDateTime_GET_YEAR(obj: *PyObject) c_int {
    const date: *c.PyDateTime_Date = @ptrCast(obj);
    return (@as(c_int, date.data[0]) << 8) | @as(c_int, date.data[1]);
}

/// Get month from date/datetime
pub fn PyDateTime_GET_MONTH(obj: *PyObject) c_int {
    const date: *c.PyDateTime_Date = @ptrCast(obj);
    return @as(c_int, date.data[2]);
}

/// Get day from date/datetime
pub fn PyDateTime_GET_DAY(obj: *PyObject) c_int {
    const date: *c.PyDateTime_Date = @ptrCast(obj);
    return @as(c_int, date.data[3]);
}

/// Get hour from datetime/time
pub fn PyDateTime_DATE_GET_HOUR(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return @as(c_int, dt.data[4]);
}

/// Get minute from datetime/time
pub fn PyDateTime_DATE_GET_MINUTE(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return @as(c_int, dt.data[5]);
}

/// Get second from datetime/time
pub fn PyDateTime_DATE_GET_SECOND(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return @as(c_int, dt.data[6]);
}

/// Get microsecond from datetime/time
pub fn PyDateTime_DATE_GET_MICROSECOND(obj: *PyObject) c_int {
    const dt: *c.PyDateTime_DateTime = @ptrCast(obj);
    return (@as(c_int, dt.data[7]) << 16) | (@as(c_int, dt.data[8]) << 8) | @as(c_int, dt.data[9]);
}

/// Get hour from time object
pub fn PyDateTime_TIME_GET_HOUR(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return @as(c_int, t.data[0]);
}

/// Get minute from time object
pub fn PyDateTime_TIME_GET_MINUTE(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return @as(c_int, t.data[1]);
}

/// Get second from time object
pub fn PyDateTime_TIME_GET_SECOND(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return @as(c_int, t.data[2]);
}

/// Get microsecond from time object
pub fn PyDateTime_TIME_GET_MICROSECOND(obj: *PyObject) c_int {
    const t: *c.PyDateTime_Time = @ptrCast(obj);
    return (@as(c_int, t.data[3]) << 16) | (@as(c_int, t.data[4]) << 8) | @as(c_int, t.data[5]);
}

/// Get days from timedelta
pub fn PyDateTime_DELTA_GET_DAYS(obj: *PyObject) c_int {
    const delta: *c.PyDateTime_Delta = @ptrCast(obj);
    return delta.days;
}

/// Get seconds from timedelta
pub fn PyDateTime_DELTA_GET_SECONDS(obj: *PyObject) c_int {
    const delta: *c.PyDateTime_Delta = @ptrCast(obj);
    return delta.seconds;
}

/// Get microseconds from timedelta
pub fn PyDateTime_DELTA_GET_MICROSECONDS(obj: *PyObject) c_int {
    const delta: *c.PyDateTime_Delta = @ptrCast(obj);
    return delta.microseconds;
}
