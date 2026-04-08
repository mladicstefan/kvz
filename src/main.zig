const std = @import("std");
const debug = std.debug.print;

const data_dir_path = "/home/djamla/code/git/kvz/data/";

pub const Entry = struct {
    key_len: u32,
    value_len: u32,
    key: []const u8,
    value: []const u8,
};

const ParserError = error{
    SyntaxError,
    InvalidArguments,
    NotFound,
};

const Command = enum { GET, SET, DEL };

fn parseInputs(line: []const u8) ParserError!?Entry {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');
    while (iter.next()) |curr| {
        const cmd = std.meta.stringToEnum(Command, curr) orelse return ParserError.SyntaxError;
        switch (cmd) {
            .GET => {
                debug("get", .{});
            },
            .SET => {
                debug("set", .{});
                const key = iter.next() orelse return ParserError.InvalidArguments;
                const val = iter.next() orelse return ParserError.InvalidArguments;
                return .{
                    .key_len = @as(u32, @intCast(key.len)),
                    .value_len = @as(u32, @intCast(val.len)),
                    .key = key,
                    .value = val,
                };
            },
            .DEL => {
                debug("del", .{});
            },
        }
    }
    return null;
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var map: std.StringHashMap([]const u8) = .init(allocator);
    defer map.deinit();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout: *std.io.Writer = &stdout_writer.interface;

    var read_buff: [1024]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&read_buff);
    const stdin: *std.io.Reader = &reader.interface;
    var data_dir = try std.fs.openDirAbsolute(data_dir_path, .{});
    defer data_dir.close();

    const database: std.fs.File = try data_dir.openFile("data.bin", .{ .mode = .read_write });
    defer database.close();

    while (true) {
        _ = try stdout.print("\nEnter a command: \n", .{});
        //actually a potential bottleneck here
        try stdout.flush();

        const bare_line = try stdin.takeDelimiter('\n') orelse unreachable;
        const line = std.mem.trim(u8, bare_line, "\r");
        if (try parseInputs(line)) |entry| {
            try database.seekFromEnd(0);
            inline for (std.meta.fields(Entry)) |field| {
                const val = @field(entry, field.name);
                if (field.type == []const u8) {
                    try database.writeAll(val);
                } else {
                    try database.writeAll(std.mem.asBytes(&val));
                }
            }
        }
    }
}
