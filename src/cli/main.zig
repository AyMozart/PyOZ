const std = @import("std");
const version = @import("version");

const commands = @import("commands.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-V")) {
        printVersion();
        return;
    }

    if (std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
        return;
    }

    // Dispatch to command handlers
    if (std.mem.eql(u8, command, "init")) {
        try commands.init(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build")) {
        try commands.build(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "develop")) {
        try commands.develop(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "publish")) {
        try commands.publish(allocator, args[2..]);
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
        std.process.exit(1);
    }
}

fn printVersion() void {
    std.debug.print("pyoz {s}\n", .{version.string});
}

fn printUsage() void {
    std.debug.print(
        \\pyoz {s} - Build and package Zig Python extensions
        \\
        \\Usage: pyoz <command> [options]
        \\
        \\Commands:
        \\  init          Create a new PyOZ project
        \\  build         Build the extension module and create wheel
        \\  develop       Build and install in development mode
        \\  publish       Publish to PyPI
        \\
        \\Options:
        \\  -h, --help     Show this help message
        \\  -V, --version  Show version information
        \\
        \\Run 'pyoz <command> --help' for more information on a command.
        \\
    , .{version.string});
}
