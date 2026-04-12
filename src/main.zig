const std = @import("std");
const debug = std.debug.print;
const posix = std.posix;
const log = std.log.debug;
const expect = std.testing.expect;
const assert = std.debug.assert;

const Dispatcher = @import("Dispatcher.zig");
const Parser = @import("Parser.zig");
const SwissTable = @import("SwissTable.zig");
const Store = @import("Store.zig");
const builtin = @import("builtin");

comptime {
    const v = builtin.zig_version;
    if (v.major != 0 or v.minor < 16) {
        @compileError("requires Zig 0.16.x");
    }
}

const ClientCtx = struct {
    io: std.Io,
    stream: std.Io.net.Stream,
    store: Store, // or whatever type SwissTable.init returns
};

pub fn main(init: std.process.Init.Minimal) !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer assert(debug_allocator.deinit() == .ok);
    const gpa = debug_allocator.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{
        .argv0 = .init(init.args),
        .environ = init.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();

    return serverMain(gpa, io);
}

fn handleClient(io: std.Io, stream: std.Io.net.Stream, store: *Store) !void {
    var s = stream;
    defer s.close(io);
    var read_buffer: [4096]u8 = undefined;
    var stream_reader = s.reader(io, &read_buffer);
    const rdr = &stream_reader.interface;
    var parser = Parser.init();
    while (true) {
        var out_buf: [1024]u8 = undefined;
        var out: std.Io.Writer = .fixed(&out_buf);
        _ = rdr.streamDelimiter(&out, '\n') catch break;
        _ = rdr.toss(1);
        const query = out.buffered();
        if (query.len == 0) continue;
        parser.parse(query);
        Dispatcher.dispatch(parser.tokens[0..parser.token_count], store.*) catch |err| {
            std.debug.print("dispatch err: {}\n", .{err});
            continue;
        };
    }
}

pub fn serverMain(gpa: std.mem.Allocator, io: std.Io) !void {
    const PORT = 25556;
    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", PORT);
    var server = try std.Io.net.IpAddress.listen(&address, io, .{ .reuse_address = true });
    log("Listening on port:{d}...\n", .{PORT});

    var store = try SwissTable.init(10, gpa, io);
    defer {
        const st: *SwissTable = @ptrCast(@alignCast(store.ptr));
        st.deinit();
    }

    while (true) {
        const stream = try server.accept(io);

        var future = io.async(handleClient, .{ io, stream, &store });
        defer future.cancel(io) catch unreachable;

        future.await(io) catch |err| {
            std.debug.print("client err: {}\n", .{err});
        };
    }
}
