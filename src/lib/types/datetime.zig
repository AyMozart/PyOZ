//! DateTime types for Python interop
//!
//! Provides Date, Time, DateTime, and TimeDelta types compatible with
//! Python's datetime module.

/// A date type (year, month, day)
pub const Date = struct {
    const _is_pyoz_date = true;

    year: i32,
    month: u8,
    day: u8,

    pub fn init(year: i32, month: u8, day: u8) Date {
        return .{ .year = year, .month = month, .day = day };
    }
};

/// A time type (hour, minute, second, microsecond)
pub const Time = struct {
    const _is_pyoz_time = true;

    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,

    pub fn init(hour: u8, minute: u8, second: u8) Time {
        return .{ .hour = hour, .minute = minute, .second = second, .microsecond = 0 };
    }

    pub fn initWithMicrosecond(hour: u8, minute: u8, second: u8, microsecond: u32) Time {
        return .{ .hour = hour, .minute = minute, .second = second, .microsecond = microsecond };
    }
};

/// A datetime type (date + time)
pub const DateTime = struct {
    const _is_pyoz_datetime = true;

    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    microsecond: u32 = 0,

    pub fn init(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8) DateTime {
        return .{ .year = year, .month = month, .day = day, .hour = hour, .minute = minute, .second = second, .microsecond = 0 };
    }

    pub fn initWithMicrosecond(year: i32, month: u8, day: u8, hour: u8, minute: u8, second: u8, microsecond: u32) DateTime {
        return .{ .year = year, .month = month, .day = day, .hour = hour, .minute = minute, .second = second, .microsecond = microsecond };
    }

    pub fn date(self: DateTime) Date {
        return .{ .year = self.year, .month = self.month, .day = self.day };
    }

    pub fn time(self: DateTime) Time {
        return .{ .hour = self.hour, .minute = self.minute, .second = self.second, .microsecond = self.microsecond };
    }
};

/// A timedelta type (duration)
pub const TimeDelta = struct {
    const _is_pyoz_timedelta = true;

    days: i32,
    seconds: i32,
    microseconds: i32,

    pub fn init(days: i32, seconds: i32, microseconds: i32) TimeDelta {
        return .{ .days = days, .seconds = seconds, .microseconds = microseconds };
    }

    /// Create from total seconds
    pub fn fromSeconds(total_seconds: i64) TimeDelta {
        const days: i32 = @intCast(@divFloor(total_seconds, 86400));
        const remaining: i32 = @intCast(@mod(total_seconds, 86400));
        return .{ .days = days, .seconds = remaining, .microseconds = 0 };
    }

    /// Get total seconds
    pub fn totalSeconds(self: TimeDelta) i64 {
        return @as(i64, self.days) * 86400 + @as(i64, self.seconds);
    }
};
