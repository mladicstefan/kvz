const std = @import("std");
const debug = std.debug.print;
const net = std.net;
const posix = std.posix;
const log = std.log;

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

const KvError = std.fs.File.WriteError || std.fs.File.SeekError || std.mem.Allocator.Error || ParserError || std.fs.File.ReadError || std.io.Writer.Error;

const Command = enum { GET, SET, DEL, LS };

fn parseInputs(allocator: std.mem.Allocator, line: []const u8, map: *std.StringHashMap([]const u8), database: std.fs.File, writer: *std.io.Writer) KvError!?Entry {
    var iter = std.mem.tokenizeScalar(u8, line, ' ');
    while (iter.next()) |curr| {
        const cmd = std.meta.stringToEnum(Command, curr) orelse return ParserError.SyntaxError;
        switch (cmd) {
            .GET => {
                const key = iter.next() orelse return ParserError.InvalidArguments;
                const entry = map.get(key);
                if (entry) |e| {
                    try writer.print("{s}: {s}\n", .{ key, e });
                } else {
                    try writer.print("NOT FOUND\n", .{});
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
                try writer.print("OK\n", .{});
                return entry;
            },
            .DEL => {
                const key = iter.next() orelse return ParserError.InvalidArguments;
                if (map.fetchRemove(key)) |removed| {
                    allocator.free(removed.key);
                    allocator.free(removed.value);
                    try writer.print("DEL {s}\n", .{key});
                } else {
                    try writer.print("NOT FOUND\n", .{});
                }
            },
            .LS => {
                var it = map.iterator();
                while (it.next()) |entry| {
                    try writer.print("{s}: {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
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

    var map: std.StringHashMap([]const u8) = .init(allocator);
    defer map.deinit();

    const PORT = 25556;
    const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, PORT);
    const server = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(server);

    try posix.setsockopt(server, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(server, &address.any, address.getOsSockLen());
    try posix.listen(server, 128);
    debug("Listening on port:{d}...\n", .{PORT});

    var data_dir = std.fs.openDirAbsolute(DATA_PATH, .{}) catch |err| switch (err) {
        error.FileNotFound => blk: {
            try std.fs.makeDirAbsolute(DATA_PATH);
            break :blk try std.fs.openDirAbsolute(DATA_PATH, .{});
        },
        else => return err,
    };

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
        var client_addr: net.Address = undefined;
        var addr_len: posix.socklen_t = @sizeOf(net.Address);

        const client = try posix.accept(server, &client_addr.any, &addr_len, 0);
        defer posix.close(client);
        log.info("accepted connection from {}", .{client_addr.in.sa.addr});

        const stream: net.Stream = .{ .handle = client };
        var write_buf: [4096]u8 = undefined;
        var writer = stream.writer(&write_buf);
        while (true) {
            var buf: [1024]u8 = undefined;
            const n = posix.read(client, &buf) catch break;
            if (n == 0) break; // client disconnected
            log.info("received {d} bytes: {s}", .{ n, buf[0..n] });

            const line = std.mem.trim(u8, buf[0..n], "\r\n");
            _ = parseInputs(allocator, line, &map, database, &writer.interface) catch |err| {
                log.err("error: {any}", .{err});
                var err_buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&err_buf, "ERR: {s}\n", .{@errorName(err)}) catch "ERR: unknown\n";
                writer.interface.writeAll(msg) catch break;
                writer.interface.flush() catch break;
                continue;
            };
            writer.interface.flush() catch break;
        }
    }
}
