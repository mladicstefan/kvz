//https://go.dev/blog/swisstable
//https://abseil.io/about/design/swisstables
//https://en.wikipedia.org/wiki/Avalanche_effect
const std = @import("std");
const debug = std.debug.print;
const expect = std.testing.expect;
const SimdEql = @import("SIMDStrings.zig");

const GROUP_SIZE = 16;

const SwissTable = @This();
capacity_log2: u8, //needs to be power of 2, realloc when ~87.5% full
size: u32, //how many elements in the map, double check if u32 later
control: []Metadata,
slots: []Entry,
allocator: std.mem.Allocator,
seed: u64,

pub const Hash = u64;
const FingerPrint = u7;

const Entry = struct { K: []u8, V: u64 };
const Metadata = packed struct {
    fingerprint: FingerPrint = free,
    used: u1 = 0,

    comptime {
        std.debug.assert(@sizeOf(Metadata) == 1);
        std.debug.assert(@bitSizeOf(Metadata) == 8);
    }
    const free: FingerPrint = 0;
    const tombstone: FingerPrint = 1;

    const slot_free = @as(u8, @bitCast(Metadata{ .fingerprint = free }));
    const slot_tombstone = @as(u8, @bitCast(Metadata{ .fingerprint = tombstone }));

    pub fn isUsed(self: Metadata) bool {
        return self.used == 1;
    }

    pub fn isTombstone(self: Metadata) bool {
        return @as(u8, @bitCast(self)) == slot_tombstone;
    }

    pub fn isFree(self: Metadata) bool {
        return @as(u8, @bitCast(self)) == slot_free;
    }

    pub fn takeFingerprint(hash: Hash) FingerPrint {
        const hash_bits = @typeInfo(Hash).int.bits;
        const fp_bits = @typeInfo(FingerPrint).int.bits;
        return @as(FingerPrint, @truncate(hash >> (hash_bits - fp_bits)));
    }

    pub fn fill(self: *Metadata, fp: FingerPrint) void {
        self.used = 1;
        self.fingerprint = fp;
    }

    pub fn remove(self: *Metadata) void {
        self.used = 0;
        self.fingerprint = tombstone;
    }
};

pub fn init(capacity_log2: u8, allocator: std.mem.Allocator) !SwissTable {
    const capacity = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(capacity_log2));
    const control = try allocator.alloc(Metadata, capacity);
    const slots = try allocator.alloc(Entry, capacity);
    // Zero-out control (everything is free)
    @memset(control, Metadata{ .fingerprint = Metadata.free, .used = 0 });
    return .{
        .capacity_log2 = capacity_log2,
        .control = control,
        .slots = slots,
        .size = 0,
        .allocator = allocator,
    };
}

pub fn deinit(self: *@This()) void {
    self.allocator.free(self.control);
    self.allocator.free(self.slots);
}

fn hashIt(seed: Hash, input: []const u8) Hash {
    return std.hash.Wyhash.hash(seed, input);
}

fn matchH2(self: @This(), group_index: usize, fingerprint: FingerPrint) u16 {
    const start = group_index * GROUP_SIZE;
    const control_vec: @Vector(GROUP_SIZE, u8) = @bitCast(self.control[start..][0..GROUP_SIZE].*);
    const fp_byte = @as(u8, @bitCast(Metadata{ .fingerprint = fingerprint, .used = 1 }));
    const fp_vec: @Vector(GROUP_SIZE, u8) = @splat(fp_byte);
    const res = control_vec == fp_vec;
    return @bitCast(res);
}

fn matchEmpty(self: @This(), group_index: usize) u16 {
    const start = group_index * GROUP_SIZE;
    const control_vec: @Vector(GROUP_SIZE, u8) = @bitCast(self.control[start..][0..GROUP_SIZE].*);
    const empty_vec: @Vector(GROUP_SIZE, u8) = @splat(0x00);
    return @bitCast(control_vec == empty_vec);
}

pub fn get(self: @This(), key: []const u8) ?u64 {
    const hash = hashIt(self.seed, key);
    const H1 = hash >> 7;
    const H2 = Metadata.takeFingerprint(hash);
    //round down to start of group
    const num_groups = (@as(usize, 1) << self.capacity_log2) / GROUP_SIZE;
    var group = (H1 % num_groups);

    while (true) {
        var match_mask = self.matchH2(group, H2);
        const count = @popCount(match_mask);
        for (0..count) |_| {
            const bit = @ctz(match_mask);
            const slot_idx = group * GROUP_SIZE + bit;
            if (SimdEql(key, self.slots[slot_idx].K)) {
                return self.slots[slot_idx].V;
            }
            match_mask &= match_mask - 1;
        }

        if (self.matchEmpty(group) != 0) {
            return null;
        }

        group = (group + 1) % num_groups;
    }
    return null;
}

test "matchEmpty" {
    const allocator = std.testing.allocator;
    var st: SwissTable = try init(@as(u6, 4), allocator);
    defer st.deinit();

    for (0..16) |i| {
        st.control[i].fill(42);
    }

    st.control[0] = Metadata{ .fingerprint = Metadata.free, .used = 0 };
    st.control[5] = Metadata{ .fingerprint = Metadata.free, .used = 0 };
    st.control[10] = Metadata{ .fingerprint = Metadata.free, .used = 0 };

    const bitmask = st.matchEmpty(0);
    debug("{b}\n", .{bitmask});
    try expect(bitmask == ((@as(u16, 1) << @intCast(0)) | (@as(u16, 1) << @intCast(5)) | (@as(u16, 1) << @intCast(10))));
}

test "MatchH2" {
    const allocator = std.testing.allocator;
    var st: SwissTable = try init(@as(u6, 4), allocator);
    const seed = std.crypto.random.int(Hash);
    //https://en.wikipedia.org/wiki/Avalanche_effect
    const hash = hashIt(seed, @as([]const u8, "dsasd"));
    const fp = Metadata.takeFingerprint(hash);
    for (0..GROUP_SIZE) |i| {
        st.control[i].fill(fp);
    }

    const bitmask = st.matchH2(fp);
    // debug("{b}\n", .{bitmask});
    try expect(bitmask == 0xFFFF);
    try expect(bitmask == ~@as(u16, 0));
    defer st.deinit();
}

test "swisstable create and destroy / avalanche effect" {
    const allocator = std.testing.allocator;
    var st: SwissTable = try init(@as(u6, 4), allocator);
    const seed = std.crypto.random.int(Hash);
    //https://en.wikipedia.org/wiki/Avalanche_effect
    try expect(hashIt(seed, "Hello") == hashIt(seed, "Hello"));
    // Avalanche effect confirmed, so comment this out
    // debug("{d}\n", .{hashIt(seed, "Hello")});
    // debug("{d}\n", .{hashIt(seed, "Hellq")});
    // debug("{d}\n", .{hashIt(seed, "hello")});
    defer st.deinit();
}
