const std = @import("std");
const debug = std.debug.print;

const DATA_PATH = "/home/djamla/code/git/kvz/data/";
const HEADER_OFFSET = 4;

pub const Entry = struct {
    key_len: u32,
    value_len: u32,
    key: []u8,
    value: []u8,
};

const ParserError = error{
    SyntaxError,
    InvalidArguments,
    NotFound,
};

const KvError = std.fs.File.WriteError || std.fs.File.SeekError || std.mem.Allocator.Error || ParserError || std.fs.File.ReadError;

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
                    res.value_ptr.* = entry.value;
                } else {
                    try database.seekTo(0);
                    var bytes: [4]u8 = undefined;
                    _ = try database.readAll(&bytes);
                    var num: u32 = @bitCast(bytes);
                    num += 1;
                    try database.seekTo(0);
                    try database.writeAll(&std.mem.toBytes(num));
                    try database.seekFromEnd(0);
                    res.value_ptr.* = entry.value;
                    try database.seekFromEnd(0);
                    inline for (std.meta.fields(Entry)) |field| {
                        const value = @field(entry, field.name);
                        if (field.type == []u8) {
                            try database.writeAll(value);
                        } else {
                            try database.writeAll(std.mem.asBytes(&value));
                        }
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

fn sync(allocator: std.mem.Allocator, database: std.fs.File, map: *std.StringHashMap([]const u8), elems: u32) !void {
    try database.seekTo(HEADER_OFFSET);
    for (0..elems) |_| {
        var entry: Entry = undefined;

        var bytes: [4]u8 = undefined;
        _ = try database.readAll(&bytes);
        entry.key_len = @bitCast(bytes);
        _ = try database.readAll(&bytes);
        entry.value_len = @bitCast(bytes);

        entry.key = try allocator.alloc(u8, entry.key_len);
        entry.value = try allocator.alloc(u8, entry.value_len);
        _ = try database.readAll(entry.key);
        _ = try database.readAll(entry.value);

        const res = try map.getOrPut(entry.key);

        if (res.found_existing) {
            allocator.free(entry.key);
            allocator.free(res.value_ptr.*);
        }
        res.value_ptr.* = entry.value;
    }
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

    var data_dir = try std.fs.openDirAbsolute(DATA_PATH, .{});
    defer data_dir.close();

    const database = data_dir.openFile("data.bin", .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => blk: {
            const f = try data_dir.createFile("data.bin", .{ .read = true });
            try f.writeAll(&std.mem.toBytes(@as(u32, 0)));
            try f.seekTo(0);
            break :blk f;
        },
        else => return err,
    };

    defer database.close();

    var bytes: [4]u8 = undefined;
    _ = try database.readAll(&bytes);
    const num_elements: u32 = @bitCast(bytes);
    try database.seekTo(HEADER_OFFSET);

    debug("Syncing {d} elements...\n", .{num_elements});
    try sync(allocator, database, &map, num_elements);
    debug("Done, use responsibly (if possible)\n", .{});

    while (true) {
        const bare_line = try stdin.takeDelimiter('\n') orelse unreachable;
        const line = std.mem.trim(u8, bare_line, "\r");
        _ = parseInputs(allocator, line, &map, database) catch |err| {
            debug("error: {any}\n", .{err});
            continue;
        };
    }
}
