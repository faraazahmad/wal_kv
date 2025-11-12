const std = @import("std");
const wal = @import("wal");

fn run_checkpointer(journal: *wal.Journal) !void {
    try journal.run_bin_checkpointer();
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
    const wal_load_result = journal.load_wal();
    if (wal_load_result) |result| {
        if (result) {
            std.debug.print("WAL loaded.", .{});
        }
    } else |_| {
        std.debug.print("Unable to load WAL.", .{});
    }
    _ = try std.Thread.spawn(.{}, run_checkpointer, .{&journal});

    try journal.bin_set_key("hello", "world");
}
