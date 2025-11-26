const std = @import("std");

/// Simple ZIP file writer using STORE method (no compression)
/// Implements the ZIP format spec for creating wheel packages
pub const ZipWriter = struct {
    file: std.fs.File,
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(CentralDirEntry),
    bytes_written: u32,
    dos_time: u16,
    dos_date: u16,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().createFile(path, .{});

        // Get current time and convert to DOS format
        const now = std.time.timestamp();
        const dos = timestampToDos(now);

        return Self{
            .file = file,
            .allocator = allocator,
            .entries = .{},
            .bytes_written = 0,
            .dos_time = dos.time,
            .dos_date = dos.date,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.filename);
        }
        self.entries.deinit(self.allocator);
        self.file.close();
    }

    /// Add a file to the ZIP archive (STORE method - no compression)
    pub fn addFile(self: *Self, filename: []const u8, data: []const u8) !void {
        const local_header_offset = self.bytes_written;
        const size: u32 = @intCast(data.len);

        // Calculate CRC32
        const crc = std.hash.Crc32.hash(data);

        // Write local file header
        var header: [30]u8 = undefined;

        // Local file header signature (0x04034b50)
        std.mem.writeInt(u32, header[0..4], 0x04034b50, .little);
        // Version needed to extract (1.0 = 10)
        std.mem.writeInt(u16, header[4..6], 10, .little);
        // General purpose bit flag
        std.mem.writeInt(u16, header[6..8], 0, .little);
        // Compression method (0 = STORE)
        std.mem.writeInt(u16, header[8..10], 0, .little);
        // Last mod file time (DOS format)
        std.mem.writeInt(u16, header[10..12], self.dos_time, .little);
        // Last mod file date (DOS format)
        std.mem.writeInt(u16, header[12..14], self.dos_date, .little);
        // CRC-32
        std.mem.writeInt(u32, header[14..18], crc, .little);
        // Compressed size (same as uncompressed for STORE)
        std.mem.writeInt(u32, header[18..22], size, .little);
        // Uncompressed size
        std.mem.writeInt(u32, header[22..26], size, .little);
        // File name length
        std.mem.writeInt(u16, header[26..28], @intCast(filename.len), .little);
        // Extra field length
        std.mem.writeInt(u16, header[28..30], 0, .little);

        try self.file.writeAll(&header);
        try self.file.writeAll(filename);
        self.bytes_written += 30 + @as(u32, @intCast(filename.len));

        // Write file data (uncompressed)
        try self.file.writeAll(data);
        self.bytes_written += size;

        // Store entry for central directory
        try self.entries.append(self.allocator, .{
            .filename = try self.allocator.dupe(u8, filename),
            .size = size,
            .crc32 = crc,
            .local_header_offset = local_header_offset,
        });
    }

    /// Add a file from disk to the ZIP archive
    pub fn addFileFromDisk(self: *Self, filename: []const u8, disk_path: []const u8) !void {
        const data = try std.fs.cwd().readFileAlloc(self.allocator, disk_path, 100 * 1024 * 1024);
        defer self.allocator.free(data);
        try self.addFile(filename, data);
    }

    /// Finalize the ZIP file by writing central directory and end record
    pub fn finish(self: *Self) !void {
        const central_dir_offset = self.bytes_written;
        var central_dir_size: u32 = 0;

        // Write central directory entries
        for (self.entries.items) |entry| {
            var cd_header: [46]u8 = undefined;

            // Central directory file header signature (0x02014b50)
            std.mem.writeInt(u32, cd_header[0..4], 0x02014b50, .little);
            // Version made by (Unix = 3, version 2.0 = 20) -> 0x031e
            std.mem.writeInt(u16, cd_header[4..6], 0x0314, .little);
            // Version needed to extract
            std.mem.writeInt(u16, cd_header[6..8], 10, .little);
            // General purpose bit flag
            std.mem.writeInt(u16, cd_header[8..10], 0, .little);
            // Compression method (0 = STORE)
            std.mem.writeInt(u16, cd_header[10..12], 0, .little);
            // Last mod file time
            std.mem.writeInt(u16, cd_header[12..14], self.dos_time, .little);
            // Last mod file date
            std.mem.writeInt(u16, cd_header[14..16], self.dos_date, .little);
            // CRC-32
            std.mem.writeInt(u32, cd_header[16..20], entry.crc32, .little);
            // Compressed size
            std.mem.writeInt(u32, cd_header[20..24], entry.size, .little);
            // Uncompressed size
            std.mem.writeInt(u32, cd_header[24..28], entry.size, .little);
            // File name length
            std.mem.writeInt(u16, cd_header[28..30], @intCast(entry.filename.len), .little);
            // Extra field length
            std.mem.writeInt(u16, cd_header[30..32], 0, .little);
            // File comment length
            std.mem.writeInt(u16, cd_header[32..34], 0, .little);
            // Disk number start
            std.mem.writeInt(u16, cd_header[34..36], 0, .little);
            // Internal file attributes
            std.mem.writeInt(u16, cd_header[36..38], 0, .little);
            // External file attributes (Unix permissions: 0644 << 16)
            std.mem.writeInt(u32, cd_header[38..42], 0x81a40000, .little);
            // Relative offset of local header
            std.mem.writeInt(u32, cd_header[42..46], entry.local_header_offset, .little);

            try self.file.writeAll(&cd_header);
            try self.file.writeAll(entry.filename);

            central_dir_size += 46 + @as(u32, @intCast(entry.filename.len));
        }

        // Write end of central directory record
        var eocd: [22]u8 = undefined;

        // End of central directory signature (0x06054b50)
        std.mem.writeInt(u32, eocd[0..4], 0x06054b50, .little);
        // Number of this disk
        std.mem.writeInt(u16, eocd[4..6], 0, .little);
        // Disk where central directory starts
        std.mem.writeInt(u16, eocd[6..8], 0, .little);
        // Number of central directory records on this disk
        std.mem.writeInt(u16, eocd[8..10], @intCast(self.entries.items.len), .little);
        // Total number of central directory records
        std.mem.writeInt(u16, eocd[10..12], @intCast(self.entries.items.len), .little);
        // Size of central directory
        std.mem.writeInt(u32, eocd[12..16], central_dir_size, .little);
        // Offset of start of central directory
        std.mem.writeInt(u32, eocd[16..20], central_dir_offset, .little);
        // Comment length
        std.mem.writeInt(u16, eocd[20..22], 0, .little);

        try self.file.writeAll(&eocd);
    }
};

const CentralDirEntry = struct {
    filename: []const u8,
    size: u32,
    crc32: u32,
    local_header_offset: u32,
};

/// Convert Unix timestamp to DOS date/time format
fn timestampToDos(timestamp: i64) struct { time: u16, date: u16 } {
    // Convert to epoch seconds then to broken-down time
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(0, timestamp)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1;

    const hour = day_seconds.getHoursIntoDay();
    const minute = day_seconds.getMinutesIntoHour();
    const second = day_seconds.getSecondsIntoMinute();

    // DOS date: bits 0-4 = day, bits 5-8 = month, bits 9-15 = year - 1980
    // DOS time: bits 0-4 = second/2, bits 5-10 = minute, bits 11-15 = hour
    const dos_year: u16 = if (year >= 1980) @intCast(year - 1980) else 0;

    const dos_date: u16 = (@as(u16, dos_year) << 9) | (@as(u16, month) << 5) | @as(u16, day);
    const dos_time: u16 = (@as(u16, hour) << 11) | (@as(u16, minute) << 5) | (@as(u16, second) >> 1);

    return .{ .time = dos_time, .date = dos_date };
}
