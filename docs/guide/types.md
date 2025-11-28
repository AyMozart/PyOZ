# Types

PyOZ automatically converts between Zig and Python types. This guide covers all supported types.

## Basic Types

| Zig Type | Python Type | Notes |
|----------|-------------|-------|
| `i8` - `i64`, `u8` - `u64` | `int` | Standard integers |
| `i128`, `u128` | `int` | Big integers (via string conversion) |
| `f32`, `f64` | `float` | Floating point |
| `bool` | `bool` | Boolean |
| `[]const u8` | `str` | Strings (input and output) |
| `void` | `None` | No return value |

## Optional Types

Use `?T` for values that may be `None`:

- As parameters: `?[]const u8` becomes an optional keyword argument
- As return type: return `null` to return `None`

When returning `null`, if a Python exception is set, it becomes an error indicator; otherwise returns `None`.

## Special Types

PyOZ provides wrapper types for Python's specialized types:

| Type | Python Equivalent | Usage |
|------|-------------------|-------|
| `pyoz.Complex` | `complex` | 64-bit complex numbers |
| `pyoz.Complex32` | `complex` | 32-bit complex (NumPy) |
| `pyoz.Date` | `datetime.date` | Date values |
| `pyoz.Time` | `datetime.time` | Time values |
| `pyoz.DateTime` | `datetime.datetime` | Combined date/time |
| `pyoz.TimeDelta` | `datetime.timedelta` | Time differences |
| `pyoz.Bytes` | `bytes` | Byte sequences |
| `pyoz.Path` | `str` or `pathlib.Path` | File paths (accepts both) |
| `pyoz.Decimal` | `decimal.Decimal` | Arbitrary precision decimals |

Create them with `.init()` methods (e.g., `pyoz.Date.init(2024, 12, 25)`).

## Collections

### Input (Zero-Copy Views)

These provide read access to Python collections without copying:

| Type | Python Source | Key Methods |
|------|---------------|-------------|
| `pyoz.ListView(T)` | `list` | `.len()`, `.get(i)`, `.iterator()` |
| `pyoz.DictView(K, V)` | `dict` | `.len()`, `.get(key)`, `.contains(key)`, `.iterator()` |
| `pyoz.SetView(T)` | `set`/`frozenset` | `.len()`, `.contains(val)`, `.iterator()` |
| `pyoz.IteratorView(T)` | Any iterable | `.next()` - works with generators, ranges, etc. |

### Output

| Type | Creates | Example |
|------|---------|---------|
| `[]const T` | `list` | `return &[_]i64{1, 2, 3};` |
| `pyoz.Dict(K, V)` | `dict` | `.{ .entries = &.{...} }` |
| `pyoz.Set(T)` | `set` | `.{ .items = &.{...} }` |
| `pyoz.FrozenSet(T)` | `frozenset` | `.{ .items = &.{...} }` |
| `pyoz.Iterator(T)` | `list` | `.{ .items = &.{...} }` (eager) |
| `pyoz.LazyIterator(T, State)` | iterator | Lazy on-demand iteration |
| `struct { T, U }` | `tuple` | `return .{ a, b };` |

### Iterator vs LazyIterator

PyOZ provides two ways to return iterable data:

**`Iterator(T)`** - Eager iteration, converts to Python list immediately:

```zig
fn get_fibonacci() pyoz.Iterator(i64) {
    const fibs = [_]i64{ 1, 1, 2, 3, 5, 8, 13, 21, 34, 55 };
    return .{ .items = &fibs };
}
// Python: get_fibonacci() returns [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]
```

**`LazyIterator(T, State)`** - Lazy iteration, generates values on-demand:

```zig
const RangeState = struct {
    current: i64,
    end: i64,
    step: i64,

    pub fn next(self: *@This()) ?i64 {
        if (self.current >= self.end) return null;
        const val = self.current;
        self.current += self.step;
        return val;
    }
};

fn lazy_range(start: i64, end: i64, step: i64) pyoz.LazyIterator(i64, RangeState) {
    return .{ .state = .{ .current = start, .end = end, .step = step } };
}
// Python: lazy_range(0, 1000000, 1) returns an iterator (memory efficient!)
```

**When to use which:**

| Use Case | Type | Reason |
|----------|------|--------|
| Small, known data | `Iterator(T)` | Simple, returns a list |
| Large/infinite sequences | `LazyIterator(T, State)` | Memory efficient |
| Need random access | `Iterator(T)` | Lists support indexing |
| Stream processing | `LazyIterator(T, State)` | Values computed on-demand |

### View Types (Input Only)

View types provide **zero-copy read access** to Python collections. They are **consumer-only** - you can receive them as function parameters but cannot return them. This asymmetry exists because:

1. Views hold references to Python objects that must remain valid
2. The underlying Python object owns the memory
3. Returning a view would require the caller to manage Python object lifetimes

For returning collections, use the producer types (`Set`, `Dict`, `Iterator`, etc.) which create new Python objects.

### Fixed-Size Arrays

`[N]T` accepts a Python list of exactly N elements. Wrong size raises an error.

## NumPy Arrays (Buffer Protocol)

Zero-copy access to NumPy arrays:

| Type | Access | Use Case |
|------|--------|----------|
| `pyoz.BufferView(T)` | Read-only | Analysis, computation |
| `pyoz.BufferViewMut(T)` | Read-write | In-place modification |

**Supported element types:** `f32`, `f64`, `i8`-`i64`, `u8`-`u64`, `pyoz.Complex`, `pyoz.Complex32`

**Methods:** `.len()`, `.rows()`, `.cols()`, `.data` (slice), `.fill(value)` (mutable only)

Access data directly via `.data` slice for maximum performance.

## Class Instances

Pass your PyOZ classes between functions:

- `*const T` - Read-only access to instance
- `*T` - Mutable access to instance

The class must be registered in the same module.

## Raw Python Objects

For advanced cases, use `*pyoz.PyObject` to accept any Python object. You're responsible for reference counting and type checking.

## Type Conversion Summary

| Direction | Zig | Python |
|-----------|-----|--------|
| Both | Integers, floats, bool, strings | int, float, bool, str |
| Both | `?T` | T or None |
| Both | Special types (Complex, DateTime, etc.) | Corresponding Python types |
| Input only | View types (ListView, BufferView, etc.) | list, dict, set, ndarray |
| Input only | `*const T`, `*T` | Class instances |
| Input only | `[N]T` | list (exact size) |
| Output only | Slices, Dict, Set | list, dict, set |
| Output only | Anonymous struct | tuple |

## Next Steps

- [Errors](errors.md) - Exception handling
- [Functions](functions.md) - Function definitions
- [Classes](classes.md) - Class definitions
