const std = @import("std");
const wal = @import("wal");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var kv_store = std.StringHashMap(enum { key, value }).init(allocator);
    defer kv_store.deinit();

    try wal.set_key("hello", "world");
}
