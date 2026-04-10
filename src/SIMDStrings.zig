const expect = @import("std").testing.expect;
const MAX_LEN = 32;

pub fn simdEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.len > MAX_LEN or b.len > MAX_LEN) return false;
    // maybe someday....
    // const isEqlLen = @intFromBool(a.len == b.len);
    // const isSafe = @intFromBool(a.len < MAX_CMD_LEN and b.len < MAX_LEN);
    // const valid = isEqlLen & isSafe;

    const len = a.len;

    var buf1: [MAX_LEN]u8 = [_]u8{0} ** MAX_LEN;
    var buf2: [MAX_LEN]u8 = [_]u8{0} ** MAX_LEN;

    @memcpy(buf1[0..len], a[0..len]);
    @memcpy(buf2[0..len], b[0..len]);

    const v1: @Vector(MAX_LEN, u8) = buf1;
    const v2: @Vector(MAX_LEN, u8) = buf2;

    const mask: @Vector(MAX_LEN, u8) = @splat(0x20);
    // mask to make it case insensitive
    // Example 1:
    // A (0x41)  01000001
    // OR (0x20) 00100000
    // a  (0x61) 01100001

    // Example 2:
    // a  (0x61) 01100001
    // OR (0x20) 00100000   OR(1,1) = 1
    // a  (0x61) 01100001
    // Works only on ASCII tho

    return @reduce(.And, (v1 | mask) == (v2 | mask));
}

pub fn simdEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    if (a.len > MAX_LEN or b.len > MAX_LEN) return false;
    // maybe someday....
    // const isEqlLen = @intFromBool(a.len == b.len);
    // const isSafe = @intFromBool(a.len < MAX_CMD_LEN and b.len < MAX_LEN);
    // const valid = isEqlLen & isSafe;

    const len = a.len;

    var buf1: [MAX_LEN]u8 = [_]u8{0} ** MAX_LEN;
    var buf2: [MAX_LEN]u8 = [_]u8{0} ** MAX_LEN;

    @memcpy(buf1[0..len], a[0..len]);
    @memcpy(buf2[0..len], b[0..len]);

    const v1: @Vector(MAX_LEN, u8) = buf1;
    const v2: @Vector(MAX_LEN, u8) = buf2;

    return @reduce(.And, v1 == v2);
}
test "simdEql" {
    try expect(simdEql("Hello", "Hello"));
    try expect(!simdEql("Hesadas", "dasdasasd"));
    try expect(!simdEql("Gello", "Hello"));
    try expect(!simdEql("SET", "set"));
}

test "simdEqlIgnoreCase" {
    try expect(simdEqlIgnoreCase("Hello", "Hello"));
    try expect(!simdEqlIgnoreCase("Hesadas", "dasdasasd"));
    try expect(!simdEqlIgnoreCase("Gello", "Hello"));
    try expect(simdEqlIgnoreCase("SET", "set"));
}

// SIMD v1 vs normal
// --- Random strings (len 10-15), 10000000 iterations ---
// std.mem.eql: 7184395864ns total, 718ns/op
// SIMD:        6313242855ns total, 631ns/op
// SIMD wins by 12.1%

//SIMD v2
// --- Random strings (len 10-15), 1000000 iterations ---
// SIMD:        751804954ns total, 751ns/op

// fn randomString(prng: *std.Random.Xoshiro256, buf: *[MAX_LEN]u8) []u8 {
//     const len: usize = 10 + prng.random().uintLessThan(usize, 6); // 10..15
//     for (buf[0..len]) |*c| {
//         c.* = 'a' + prng.random().uintLessThan(u8, 26);
//     }
//     return buf[0..len];
// }
//
// test "Benchmark random strings, branch-heavy" {
//     var prng = std.Random.Xoshiro256.init(0xDEADBEEF);
//     const ITERATIONS = 1_000_000;
//
//     // Pre-generate string pairs so generation cost isn't in the benchmark
//     const PREGEN = 1024;
//     var bufs1: [PREGEN][MAX_LEN]u8 = undefined;
//     var bufs2: [PREGEN][MAX_LEN]u8 = undefined;
//     var slices1: [PREGEN][]u8 = undefined;
//     var slices2: [PREGEN][]u8 = undefined;
//
//     for (0..PREGEN) |i| {
//         slices1[i] = randomString(&prng, &bufs1[i]);
//         slices2[i] = randomString(&prng, &bufs2[i]);
//     }
//
//     var timer = try std.time.Timer.start();
//
//     // -- Benchmark SIMD --
//     timer.reset();
//     for (0..ITERATIONS) |i| {
//         const idx = i % PREGEN;
//         var result = simdEqlIgnoreCase(slices1[idx], slices2[idx]);
//         std.mem.doNotOptimizeAway(&result);
//     }
//     const simd_ns = timer.read();
//
//     std.debug.print("\n--- Random strings (len 10-15), {} iterations ---\n", .{ITERATIONS});
//     std.debug.print("SIMD:        {}ns total, {}ns/op\n", .{ simd_ns, simd_ns / ITERATIONS });
// }
