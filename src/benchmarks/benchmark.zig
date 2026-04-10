const std = @import("std");
const net = std.net;
const posix = std.posix;

pub fn main() !void {
    const addr = net.Address.initIp4(.{ 127, 0, 0, 1 }, 25556);
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(sock);
    try posix.connect(sock, &addr.any, addr.getOsSockLen());

    const N = 1_000_000;
    var send_buf: [64]u8 = undefined;
    var recv_buf: [128]u8 = undefined;

    var timer = try std.time.Timer.start();

    for (0..N) |i| {
        const msg = std.fmt.bufPrint(&send_buf, "SET key{d} val{d}\n", .{ i, i }) catch unreachable;
        _ = try posix.write(sock, msg);
        _ = try posix.read(sock, &recv_buf);
    }

    const elapsed_ns = timer.read();
    const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
    const ops_per_sec = @as(f64, N) / elapsed_s;

    std.debug.print("{d} inserts in {d:.2}s ({d:.0} ops/sec)\n", .{ N, elapsed_s, ops_per_sec });
}
