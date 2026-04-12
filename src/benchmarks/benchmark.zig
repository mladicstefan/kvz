const std = @import("std");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa = debug_allocator.allocator();
    var threaded: std.Io.Threaded = .init(gpa, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const addr: std.Io.net.IpAddress = try .parse("127.0.0.1", 25556);
    var sock = try addr.connect(io, .{ .mode = .stream });
    defer sock.close(io);

    const N = 1_000_000;
    var send_buf: [64]u8 = undefined;
    // var recv_buf: [128]u8 = undefined;

    var w = sock.writer(io, &.{});
    // var r = sock.reader(io, &.{});

    const start = std.Io.Clock.now(.awake, io);

    for (0..N) |i| {
        const msg = std.fmt.bufPrint(&send_buf, "SET key{d} val{d}\n", .{ i, i }) catch unreachable;
        try w.interface.writeAll(msg);
    }

    const end = std.Io.Clock.now(.awake, io);
    const elapsed_ns = start.durationTo(end).toNanoseconds();
    const elapsed_s: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const ops_per_sec: f64 = @as(f64, N) / elapsed_s;
    std.debug.print("{d} inserts in {d:.2}s ({d:.0} ops/sec)\n", .{ N, elapsed_s, ops_per_sec });
}
