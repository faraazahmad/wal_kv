const std = @import("std");
const wal = @import("wal");

fn run_checkpointer(journal: *wal.Journal) !void {
    try journal.run_checkpointer();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var kv_store = std.StringHashMap([]const u8).init(allocator);
    defer kv_store.deinit();

    var journal = wal.Journal{
        .allocator = allocator,
        .store = &kv_store,
    };
    try journal.pre_allocate_wal();
    _ = try std.Thread.spawn(.{}, run_checkpointer, .{&journal});

    try journal.set_key("hello", "world");
}
