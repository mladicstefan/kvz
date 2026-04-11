//https://go.dev/blog/swisstable
//https://abseil.io/about/design/swisstables
//https://en.wikipedia.org/wiki/Avalanche_effect
const std = @import("std");
const debug = std.debug.print;
const expect = std.testing.expect;
const SimdStrings = @import("SIMDStrings.zig");
const Store = @import("Store.zig");

const MAX_KEY_LEN = 32;
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

const Entry = struct { key_len: usize, K: [MAX_KEY_LEN]u8, V: u64 };
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

const store_vtable = Store.VTable{
    .getFn = storeGet,
    .putFn = storePut,
    .delFn = storeDel,
};

fn storeGet(ptr: *anyopaque, key: []const u8) ?u64 {
    const self: *SwissTable = @ptrCast(@alignCast(ptr));
    return self.get(key);
}

fn storePut(ptr: *anyopaque, key: []const u8, val: u64) error{OutOfMemory}!void {
    const self: *SwissTable = @ptrCast(@alignCast(ptr));
    _ = try self.put(key, val);
}

fn storeDel(ptr: *anyopaque, key: []const u8) bool {
    var self: *SwissTable = @ptrCast(@alignCast(ptr));
    return self.del(key);
}

fn randomSeed(io: std.Io) !Hash {
    var buf: [@sizeOf(Hash)]u8 = undefined;
    try io.randomSecure(&buf);
    return @bitCast(buf);
}

pub fn init(capacity_log2: u8, allocator: std.mem.Allocator, io: std.Io) !Store {
    const capacity = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(capacity_log2));
    const control = try allocator.alloc(Metadata, capacity);
    const slots = try allocator.alloc(Entry, capacity);
    @memset(control, Metadata{ .fingerprint = Metadata.free, .used = 0 });

    const self = try allocator.create(SwissTable);
    self.* = .{
        .capacity_log2 = capacity_log2,
        .control = control,
        .slots = slots,
        .size = 0,
        .seed = try randomSeed(io),
        .allocator = allocator,
    };

    return .{
        .ptr = self,
        .vtable = &store_vtable,
    };
}

pub fn deinit(self: *@This()) void {
    const allocator = self.allocator;
    allocator.free(self.control);
    allocator.free(self.slots);
    allocator.destroy(self);
}

//for testing
fn initInternal(capacity_log2: u8, allocator: std.mem.Allocator, io: std.Io) !SwissTable {
    const capacity = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(capacity_log2));
    const control = try allocator.alloc(Metadata, capacity);
    const slots = try allocator.alloc(Entry, capacity);
    @memset(control, Metadata{ .fingerprint = Metadata.free, .used = 0 });
    return .{
        .capacity_log2 = capacity_log2,
        .control = control,
        .slots = slots,
        .size = 0,
        .seed = try randomSeed(io),
        .allocator = allocator,
    };
}

fn deinitInternal(self: *SwissTable) void {
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

fn lookup(self: @This(), key: []const u8, keyHash: Hash) ?usize {
    const H1 = keyHash >> 7;
    const H2 = Metadata.takeFingerprint(keyHash);
    //round down to start of group
    //
    const num_groups = (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(self.capacity_log2))) / GROUP_SIZE;
    var group = (H1 % num_groups);

    while (true) {
        var match_mask = self.matchH2(group, H2);
        const count = @popCount(match_mask);
        for (0..count) |_| {
            const bit = @ctz(match_mask);
            const slot_idx = group * GROUP_SIZE + bit;

            const key_len = self.slots[slot_idx].key_len;
            if (SimdStrings.simdEql(key, self.slots[slot_idx].K[0..key_len])) {
                return slot_idx;
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

pub fn get(self: @This(), key: []const u8) ?u64 {
    const hash = hashIt(self.seed, key);
    const idx = lookup(self, key, hash) orelse return null;
    return self.slots[idx].V;
}

pub fn del(self: *@This(), key: []const u8) bool {
    const hash = hashIt(self.seed, key);
    const idx = lookup(self.*, key, hash) orelse return false;
    self.control[idx].remove();
    self.size -= 1;
    return true;
}

pub fn put(self: *@This(), key: []const u8, value: u64) error{OutOfMemory}!void {
    const hash = hashIt(self.seed, key);
    if (lookup(self.*, key, hash)) |i| {
        self.slots[i].V = value;
        return;
    }

    const H1 = hash >> 7;
    const H2 = Metadata.takeFingerprint(hash);
    //round down to start of group
    const num_groups = (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(self.capacity_log2))) / GROUP_SIZE;
    var group = (H1 % num_groups);

    while (true) {
        const emptyMask = self.matchEmpty(group);
        if (emptyMask != 0) {
            const bit = @ctz(emptyMask);
            const slot_idx = group * GROUP_SIZE + bit;
            self.slots[slot_idx].key_len = key.len;
            @memcpy(self.slots[slot_idx].K[0..key.len], key);
            self.slots[slot_idx].V = value;
            self.control[slot_idx].fill(H2);
            self.size += 1;
            const capacity = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(self.capacity_log2));
            if (self.size >= capacity * 7 / 8) {
                try self.resize();
            }
            return;
        }

        group = (group + 1) % num_groups;
    }
    //resize logic here probs
    unreachable;
}

fn resize(self: *@This()) error{OutOfMemory}!void {
    const old_capacity = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(self.capacity_log2));
    const new_capacity_log2 = self.capacity_log2 + 1;
    const new_capacity = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(new_capacity_log2));
    self.capacity_log2 = new_capacity_log2;

    const old_control = self.control;
    const old_slots = self.slots;
    defer self.allocator.free(old_slots);
    defer self.allocator.free(old_control);

    self.control = try self.allocator.alloc(Metadata, new_capacity);
    @memset(self.control, Metadata{ .fingerprint = Metadata.free, .used = 0 });
    self.slots = try self.allocator.alloc(Entry, new_capacity);

    self.size = 0;

    for (0..old_capacity) |i| {
        if (old_control[i].isUsed()) {
            _ = try self.put(old_slots[i].K[0..old_slots[i].key_len], old_slots[i].V);
        }
    }
}

test "resize" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var st = try initInternal(@as(u6, 4), allocator, io);
    defer st.deinitInternal();

    for (0..14) |i| {
        var buf: [8]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
        try st.put(key, @intCast(i * 10));
    }

    debug("size after fills: {d}\n", .{st.size});
    debug("capacity_log2 after fills: {d}\n", .{st.capacity_log2});
    try expect(st.size == 14);
    try expect(st.capacity_log2 == 5);

    for (0..14) |i| {
        var buf: [8]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable;
        const val = st.get(key);
        debug("get {s}: {any}\n", .{ key, val });
        try expect(val.? == @as(u64, @intCast(i * 10)));
    }
}

test "ops" {
    const allocator = std.testing.allocator;

    const io = std.testing.io;
    var st = try initInternal(@as(u6, 4), allocator, io);
    defer st.deinitInternal();

    debug("--- Insert ---\n", .{});
    try st.put("hello", 42);

    try st.put("world", 99);

    debug("size: {d}\n", .{st.size});
    try expect(st.size == 2);

    debug("--- Lookup ---\n", .{});
    const v1 = st.get("hello");
    debug("get hello: {any}\n", .{v1});
    try expect(v1.? == 42);

    const v2 = st.get("world");
    debug("get world: {any}\n", .{v2});
    try expect(v2.? == 99);
    const v3 = st.get("missing");
    debug("get missing: {any}\n", .{v3});
    try expect(v3 == null);

    debug("--- Update ---\n", .{});
    try st.put("hello", 100);

    const v4 = st.get("hello");
    debug("get hello after update: {any}\n", .{v4});
    try expect(v4.? == 100);

    debug("size after update: {d}\n", .{st.size});
    try expect(st.size == 2);

    debug("--- Delete ---\n", .{});
    const d1 = st.del("hello");
    debug("del hello: {any}\n", .{d1});
    try expect(d1 == true);

    const v5 = st.get("hello");
    debug("get hello after del: {any}\n", .{v5});
    try expect(v5 == null);

    const d2 = st.del("nonexistent");
    debug("del nonexistent: {any}\n", .{d2});
    try expect(d2 == false);

    debug("--- Reinsert ---\n", .{});
    try st.put("hello", 55);

    const v6 = st.get("hello");
    debug("get hello after reinsert: {any}\n", .{v6});
    try expect(v6.? == 55);
}

test "matchEmpty" {
    const allocator = std.testing.allocator;

    const io = std.testing.io;
    var st = try initInternal(@as(u6, 4), allocator, io);
    defer st.deinitInternal();

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

    const io = std.testing.io;
    var st = try initInternal(@as(u6, 4), allocator, io);
    const seed = try randomSeed(io);
    const hash = hashIt(seed, @as([]const u8, "dsasd"));
    const fp = Metadata.takeFingerprint(hash);
    for (0..GROUP_SIZE) |i| {
        st.control[i].fill(fp);
    }

    const bitmask = st.matchH2(0, fp);
    try expect(bitmask == 0xFFFF);
    try expect(bitmask == ~@as(u16, 0));
    defer st.deinitInternal();
}

test "swisstable create and destroy / avalanche effect" {
    const allocator = std.testing.allocator;

    const io = std.testing.io;
    var st = try initInternal(@as(u6, 4), allocator, io);

    const seed = try randomSeed(io);
    try expect(hashIt(seed, "Hello") == hashIt(seed, "Hello"));
    defer st.deinitInternal();
}
