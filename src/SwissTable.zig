//https://go.dev/blog/swisstable
//https://abseil.io/about/design/swisstables
//https://en.wikipedia.org/wiki/Avalanche_effect
const std = @import("std");
const debug = std.debug.print;

const SwissTable = @This();
capacity_log2: u8, //needs to be power of 2, realloc when ~87.5% full
size: u32, //how many elements in the map, double check if u32 later
control: []Metadata,
slots: []Entry,
allocator: std.mem.Allocator,

pub const Hash = u64;

const Entry = struct { K: []u8, V: u64 };
const Metadata = packed struct {
    fingerprint: FingerPrint = free,
    used: u1 = 0,

    comptime {
        std.debug.assert(@sizeOf(Metadata) == 1);
        std.debug.assert(@bitSizeOf(Metadata) == 8);
    }

    const FingerPrint = u7;
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

test "swisstable create and destroy / avalanche effect" {
    const allocator = std.testing.allocator;
    var st: SwissTable = try init(@as(u6, 4), allocator);
    const seed = std.crypto.random.int(Hash);
    //https://en.wikipedia.org/wiki/Avalanche_effect
    debug("{d}\n", .{hashIt(seed, "Hello")});
    debug("{d}\n", .{hashIt(seed, "Hellq")});
    debug("{d}\n", .{hashIt(seed, "hello")});
    defer st.deinit();
}
