const std = @import("std");
const wal = @import("wal");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var kv_store = std.StringHashMap(wal.HashMapData).init(allocator);
    defer kv_store.deinit();

    var journal = wal.Journal{
        .allocator = allocator,
        .config = wal.CheckpointerConfig{},
        .store = &kv_store,
    };

    try wal.set_key("hello", "world", &journal);
    try journal.run_checkpointer();
}
