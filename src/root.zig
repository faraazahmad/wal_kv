//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const CheckpointerConfig = struct {
    checkoint_time_ms: u64 = 30 * 1000, // 30 seconds
    max_wal_size_in_bytes: usize = 64 * 1024 * 1024, // 64 MB
};

pub const HashMapData = enum {
    key,
    value,
};

const WALInstruction = struct {
    op: []const u8,
    key: []const u8,
    value: []const u8,
};

pub const Journal = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8 = "/home/faraaz/.config/wal_kv/wal",
    current_wal_size: usize = 0,
    last_checkpoint_time: i64 = 0,
    config: CheckpointerConfig,
    store: *std.StringHashMap(HashMapData),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: CheckpointerConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .last_checkpoint_time = std.time.milliTimestamp(),
        };
    }

    // fn read_wal_file()

    fn run_checkpointer(self: *Self) !void {
        var file_buffer: [64 * 1024 * 1024]u8 = undefined;
        while (true) {
            const now = std.time.milliTimestamp();
            const time_since_last_checkpoint = @as(u64, @intCast(now - self.last_checkpoint_time));

            if (time_since_last_checkpoint >= self.config.checkoint_time_ms) {
                var wal_file = try std.fs.openFileAbsolute(self.file_path, .{ .mode = .read_only });
                defer wal_file.close();

                // For each line
                wal_file.reader().read(&file_buffer);
                // 0. Parse it into an instruction struct
                // 1. Flush it to disk
                // 2. Apply it to in-mem kv_store
            }
        }
    }

    fn append_op(self: *Self, op: []const u8, key: []const u8, value: []const u8) !void {
        var instruction_buf: [256]u8 = undefined;
        const instruction_str = try std.fmt.bufPrint(&instruction_buf, "{s} {s} {s}\n", .{ op, key, value });

        var wal_file = try std.fs.cwd().openFile(self.file_path, .{ .mode = .write_only, .lock = .exclusive });
        defer wal_file.close();

        try wal_file.seekFromEnd(0);
        const wirtten_size = try wal_file.write(instruction_str);
        std.debug.print("Written {d} bytes to WAL", .{wirtten_size});
    }

    // fn parse_line_to_instr(line: []const u8) !WALInstruction {}

    fn pre_allocate_wal() !void {}

    fn load_wal() !bool {}

    fn replay_wal() !void {}
};

pub fn set_key(key: []const u8, value: []const u8, journal: *Journal) !void {
    try journal.append_op("set", key, value);
}

pub fn load_kv_store() !void {}
