//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const CheckpointerConfig = struct {
    checkoint_time_ms: u64 = 30 * 1000, // 30 seconds
    max_wal_size_in_bytes: usize = 64 * 1024, // 64 kB
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

pub const JournalError = error{
    SetKeyFailed,
};

pub const Journal = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8 = "/home/faraaz/.config/wal_kv/wal",
    current_wal_size: usize = 0,
    last_checkpoint_time: i64 = 0,
    config: CheckpointerConfig = CheckpointerConfig{},
    store: *std.StringHashMap(HashMapData),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: CheckpointerConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .last_checkpoint_time = std.time.milliTimestamp(),
        };
    }

    pub fn run_checkpointer(self: *Self) !void {
        var file_buffer: [64 * 1024]u8 = undefined;
        var op_list: [3][]const u8 = undefined;
        var wal_file = try std.fs.openFileAbsolute(self.file_path, .{ .mode = .read_write });
        defer wal_file.close();

        while (true) {
            const now = std.time.milliTimestamp();
            const time_since_last_checkpoint = @as(u64, @intCast(now - self.last_checkpoint_time));
            const stat = try wal_file.stat();

            const is_checkpoint_recent = time_since_last_checkpoint < self.config.checkoint_time_ms;
            const wal_size_within_limit = stat.size < self.config.max_wal_size_in_bytes;
            if (is_checkpoint_recent and wal_size_within_limit) {
                continue;
            }

            // Read complete file into buffer
            _ = try wal_file.readAll(&file_buffer);

            var lines = std.mem.splitScalar(u8, &file_buffer, '\n');

            while (lines.next()) |line| {
                var instr_iter = std.mem.splitScalar(u8, line, ' ');
                var index: usize = 0;
                while (instr_iter.next()) |op| {
                    if (index == 3) {
                        break;
                    }

                    op_list[index] = op;

                    index += 1;
                }
                std.debug.assert(op_list.len == 3);

                const instruction = WALInstruction{
                    .op = op_list[0],
                    .key = op_list[1],
                    .value = op_list[2],
                };
                try process_instruction(instruction);
            }

            // Because of early continue, this line assumes the log has been flushed to disk
            // So clear the log
            try wal_file.setEndPos(0);
        }
    }

    fn append_op(self: *Self, op: []const u8, key: []const u8, value: []const u8) !void {
        var instruction_buf: [256]u8 = undefined;
        const instruction_str = try std.fmt.bufPrint(&instruction_buf, "{s} {s} {s}\n", .{ op, key, value });

        var wal_file = try std.fs.cwd().openFile(self.file_path, .{ .mode = .write_only, .lock = .exclusive });
        defer wal_file.close();

        try wal_file.seekFromEnd(0);
        const wirtten_size = try wal_file.write(instruction_str);
        try wal_file.sync();
        std.debug.print("Written {d} bytes to WAL\n", .{wirtten_size});
    }

    fn process_instruction(self: *Self, instruction: WALInstruction) !void {
        if (std.mem.eql([]const u8, instruction.op, "set")) {
            try self.store.put(instruction.key, instruction.value);
        } else {
            return JournalError.SetKeyFailed;
        }
        // TODO: Flush it to disk
    }

    pub fn pre_allocate_wal(self: *Self) !void {
        const file = try std.fs.createFileAbsolute(self.file_path, .{});
        defer file.close();

        const prealloc_size: usize = 128 * 1024; // 128KiB
        try file.setEndPos(prealloc_size);
    }

    fn load_wal() !bool {}

    // Go through the WAL and apply each instruction, then clear the WAL
    fn replay_wal(self: *Self) !void {
        var file_buffer: [64 * 1024]u8 = undefined;
        var op_list: [3][]const u8 = undefined;
        var wal_file = try std.fs.openFileAbsolute(self.file_path, .{ .mode = .read_write });
        defer wal_file.close();

        const stat = try wal_file.stat();
        const wal_size_within_limit = stat.size < self.config.max_wal_size_in_bytes;
        if (wal_size_within_limit) {
            return;
        }

        // Read complete file into buffer
        _ = try wal_file.readAll(&file_buffer);

        var lines = std.mem.splitScalar(u8, &file_buffer, '\n');
        while (lines.next()) |line| {
            var instr_iter = std.mem.splitScalar(u8, line, ' ');

            var index: usize = 0;
            op_list = .{ "", "", "" };
            while (instr_iter.next()) |op| {
                if (index == 3) {
                    break;
                }

                op_list[index] = op;
                index += 1;
            }

            const instruction = WALInstruction{
                .op = op_list[0],
                .key = op_list[1],
                .value = op_list[2],
            };
            try process_instruction(instruction);
        }

        // clear the log
        try wal_file.setEndPos(0);
    }
};

pub fn set_key(key: []const u8, value: []const u8, journal: *Journal) !void {
    try journal.append_op("set", key, value);
}

pub fn load_kv_store() !void {}
