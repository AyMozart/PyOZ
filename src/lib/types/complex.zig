//! Complex number types for Python interop
//!
//! Provides Complex (f64) and Complex32 (f32) types compatible with
//! Python's complex type and numpy's complex128/complex64.

/// A complex number type (complex128 - two f64s) for use with __complex__ method
/// Return this from your __complex__ method to convert to Python complex
/// Also usable with BufferView(Complex) for numpy complex128 arrays
pub const Complex = struct {
    pub const _is_pyoz_complex = true;

    real: f64,
    imag: f64,

    pub fn init(real: f64, imag: f64) Complex {
        return .{ .real = real, .imag = imag };
    }

    pub fn add(self: Complex, other: Complex) Complex {
        return .{ .real = self.real + other.real, .imag = self.imag + other.imag };
    }

    pub fn sub(self: Complex, other: Complex) Complex {
        return .{ .real = self.real - other.real, .imag = self.imag - other.imag };
    }

    pub fn mul(self: Complex, other: Complex) Complex {
        return .{
            .real = self.real * other.real - self.imag * other.imag,
            .imag = self.real * other.imag + self.imag * other.real,
        };
    }

    pub fn conjugate(self: Complex) Complex {
        return .{ .real = self.real, .imag = -self.imag };
    }

    pub fn magnitude(self: Complex) f64 {
        return @sqrt(self.real * self.real + self.imag * self.imag);
    }
};

/// A 32-bit complex number type (complex64 - two f32s)
/// Usable with BufferView(Complex32) for numpy complex64 arrays
pub const Complex32 = struct {
    pub const _is_pyoz_complex = true;

    real: f32,
    imag: f32,

    pub fn init(real: f32, imag: f32) Complex32 {
        return .{ .real = real, .imag = imag };
    }

    pub fn add(self: Complex32, other: Complex32) Complex32 {
        return .{ .real = self.real + other.real, .imag = self.imag + other.imag };
    }

    pub fn sub(self: Complex32, other: Complex32) Complex32 {
        return .{ .real = self.real - other.real, .imag = self.imag - other.imag };
    }

    pub fn mul(self: Complex32, other: Complex32) Complex32 {
        return .{
            .real = self.real * other.real - self.imag * other.imag,
            .imag = self.real * other.imag + self.imag * other.real,
        };
    }

    pub fn conjugate(self: Complex32) Complex32 {
        return .{ .real = self.real, .imag = -self.imag };
    }

    pub fn magnitude(self: Complex32) f32 {
        return @sqrt(self.real * self.real + self.imag * self.imag);
    }

    /// Convert to Complex (f64)
    pub fn toComplex(self: Complex32) Complex {
        return .{ .real = @floatCast(self.real), .imag = @floatCast(self.imag) };
    }
};
