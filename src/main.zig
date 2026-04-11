const std = @import("std");
const debug = std.debug.print;
const posix = std.posix;
const log = std.log.debug;
const expect = std.testing.expect;

const Dispatcher = @import("Dispatcher.zig");
const Parser = @import("Parser.zig");
const SwissTable = @import("SwissTable.zig");
const builtin = @import("builtin");

comptime {
    const v = builtin.zig_version;
    if (v.major != 0 or v.minor < 16) {
        @compileError("requires Zig 0.16.x");
    }
}

pub fn main() !void {
    const PORT = 25556;
    // const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, PORT);

    // const server = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    // defer posix.close(server);

    // try posix.setsockopt(server, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    // try posix.bind(server, &address.any, address.getOsSockLen());
    // try posix.listen(server, 128);
    log("Listening on port:{d}...\n", .{PORT});

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) expect(false) catch @panic("Memory Leak");
    }

    var io_threaded = std.Io.Threaded.init(allocator, .{});
    defer io_threaded.deinit();
    const io = io_threaded.io();

    const store = try SwissTable.init(10, allocator, io);
    defer {
        const st: *SwissTable = @ptrCast(@alignCast(store.ptr));
        st.deinit();
    }

    var parser = Parser.init();
    const query: []const u8 = "SET foo 42";
    parser.parse(query);

    try Dispatcher.dispatch(parser.tokens[0..parser.token_count], store);

    const val = store.get("foo");
    debug("foo = {any}\n", .{val});
}
