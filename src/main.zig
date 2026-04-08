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

const KvError = std.fs.File.WriteError || std.fs.File.SeekError || std.mem.Allocator.Error || ParserError;

const Command = enum { GET, SET, DEL, LS };

fn parseInputs(allocator: std.mem.Allocator, line: []const u8, map: *std.StringHashMap([]const u8), database: std.fs.File) KvError!?Entry {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');
    while (iter.next()) |curr| {
        const cmd = std.meta.stringToEnum(Command, curr) orelse return ParserError.SyntaxError;
        switch (cmd) {
            .GET => {
                const key = iter.next() orelse return ParserError.InvalidArguments;
                const entry = map.get(key);
                if (entry) |e| {
                    debug("{s}: {s}\n", .{ key, e });
                }
            },
            .SET => {
                const key = try allocator.dupe(u8, iter.next() orelse return ParserError.InvalidArguments);
                const val = try allocator.dupe(u8, iter.next() orelse return ParserError.InvalidArguments);
                if (iter.next() != null) return ParserError.InvalidArguments;
                const entry: Entry = .{
                    .key_len = @as(u32, @intCast(key.len)),
                    .value_len = @as(u32, @intCast(val.len)),
                    .key = key,
                    .value = val,
                };

                const res = try map.getOrPut(entry.key);

                if (res.found_existing) {
                    allocator.free(entry.key);
                    allocator.free(res.value_ptr.*);
                }
                res.value_ptr.* = entry.value;

                try database.seekFromEnd(0);
                inline for (std.meta.fields(Entry)) |field| {
                    const value = @field(entry, field.name);
                    if (field.type == []const u8) {
                        try database.writeAll(value);
                    } else {
                        try database.writeAll(std.mem.asBytes(&value));
                    }
                }
                return entry;
            },
            .DEL => {
                const key = iter.next() orelse return ParserError.InvalidArguments;
                if (map.fetchRemove(key)) |removed| {
                    allocator.free(removed.key);
                    allocator.free(removed.value);
                    debug("DEL {s}\n", .{key});
                } else {
                    debug("NOT FOUND\n", .{});
                }
            },
            .LS => {
                var it = map.iterator();
                while (it.next()) |entry| {
                    debug("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
                }
            },
        }
    }
    return null;
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    //TODO: Map header
    var map: std.StringHashMap([]const u8) = .init(allocator);
    defer map.deinit();
    //
    // var stdout_buf: [1024]u8 = undefined;
    // var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    // const stdout: *std.io.Writer = &stdout_writer.interface;

    var read_buff: [1024]u8 = undefined;
    var reader = std.fs.File.stdin().reader(&read_buff);
    const stdin: *std.io.Reader = &reader.interface;

    var data_dir = try std.fs.openDirAbsolute(data_dir_path, .{});
    defer data_dir.close();

    const database: std.fs.File = try data_dir.openFile("data.bin", .{ .mode = .read_write });
    defer database.close();

    while (true) {
        const bare_line = try stdin.takeDelimiter('\n') orelse unreachable;
        const line = std.mem.trim(u8, bare_line, "\r");
        _ = parseInputs(allocator, line, &map, database) catch |err| {
            debug("error: {any}\n", .{err});
            continue;
        };
    }
}
