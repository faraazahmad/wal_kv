//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const CheckpointerConfig = struct {
    checkoint_time_ms: u64 = 3 * 1000, // 3 seconds
    max_wal_size_in_bytes: usize = 64 * 1024, // 64 kB
};

pub const HashMapData = union(enum) {
    key: []const u8,
    value: []const u8,
};

const INSTRUCTION_SET_SIZE: usize = 3;
const InstructionSet = enum(u8) {
    SET,
    GET,
    DELETE,
};

const WALInstruction = extern struct {
    op: InstructionSet, // index of operation in instruction set

    key_size: usize, // size of key (max 256)
    key: [256]u8,

    value_size: usize, // size of value (max 256)
    value: [256]u8,
};

const WALFile = extern struct {
    magic_number: u32 = 0xDEADBEEF, // Magic number to signify start of WAL
    version: u8, // protocol version
    instruction_set: [INSTRUCTION_SET_SIZE]InstructionSet, // Distinct instructions supported
    instructions: [256]WALInstruction, // List of instructions in the WAL
};

pub const JournalError = error{ SetKeyFailed, InvalidInstruction, WALCorrupt };

pub const Journal = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8 = "/home/faraaz/.config/wal_kv/bin_wal",
    current_wal_size: usize = 0,
    last_checkpoint_time: i64 = 0,
    config: CheckpointerConfig = CheckpointerConfig{},
    store: *std.StringHashMap([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: CheckpointerConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .last_checkpoint_time = std.time.milliTimestamp(),
        };
    }

    pub fn run_bin_checkpointer(self: *Self) !void {
        var wal: WALFile = undefined;
        const file = try std.fs.openFileAbsolute(self.file_path, .{ .mode = .read_write });
        defer file.close();

        while (true) {
            const now = std.time.milliTimestamp();
            const time_since_last_checkpoint = @as(u64, @intCast(now - self.last_checkpoint_time));
            const stat = try file.stat();

            if (stat.size == 0) {
                continue;
            }

            const is_checkpoint_recent = time_since_last_checkpoint < self.config.checkoint_time_ms;
            const wal_size_within_limit = stat.size < self.config.max_wal_size_in_bytes;
            if (is_checkpoint_recent and wal_size_within_limit) {
                continue;
            }

            // Read complete file into struct
            const bytes_read = try file.readAll(std.mem.asBytes(&wal));
            std.debug.assert(bytes_read > 0);

            for (wal.instructions) |instr| {
                std.debug.print("{s}", .{std.mem.asBytes(&instr)});
                try self.process_instruction(instr);
            }

            // Because of early continue, this line assumes the log has been flushed to disk
            // So clear the log
            // try wal_file.setEndPos(0);
            // TODO: Add a milestone with timestamp to signify when the last checkpoint was done.
        }
    }

    fn append_bin_op(self: *Self, instruction: WALInstruction) !void {
        // var instruction_buf: [256]u8 = undefined;
        // const instruction_str = try std.fmt.bufPrint(&instruction_buf, "{s} {s} {s}\n", .{ op, key, value });

        var wal_file = try std.fs.cwd().openFile(self.file_path, .{ .mode = .write_only, .lock = .exclusive });
        defer wal_file.close();

        try wal_file.seekFromEnd(0);
        const written_size = try wal_file.write(std.mem.asBytes(&instruction));
        try wal_file.sync();
        std.debug.print("Written {d} bytes to WAL\n", .{written_size});
    }

    fn process_instruction(self: *Self, instruction: WALInstruction) !void {
        switch (instruction.op) {
            InstructionSet.SET => try self.store.put(&instruction.key, &instruction.value),
            else => return JournalError.InvalidInstruction,
        }
        // TODO: Backup the data to disk
    }

    pub fn pre_allocate_wal(self: *Self) !void {
        // Try opening file, if it exists and the size is within limit, return early
        const wal_file = std.fs.openFileAbsolute(self.file_path, .{ .mode = .read_only });
        if (wal_file) |file| {
            defer file.close();
            return;
        } else |err| {
            if (err == error.FileNotFound) {
                const file = try std.fs.createFileAbsolute(self.file_path, .{});
                defer file.close();

                try file.setEndPos(@as(usize, 128 * 1024)); // 128KiB
            } else {
                return err;
            }
        }
    }

    fn load_wal() !bool {}

    pub fn bin_set_key(self: *Self, key: []const u8, value: []const u8) !void {
        if (key.len > 256 or value.len > 256) {
            return JournalError.InvalidInstruction;
        }

        var fixed_size_key: [256]u8 = undefined;
        var fixed_size_value: [256]u8 = undefined;

        @memcpy(fixed_size_key[0..key.len], key);
        @memcpy(fixed_size_value[0..value.len], value);

        try self.append_bin_op(WALInstruction{
            .op = InstructionSet.SET,
            .key_size = key.len,
            .key = fixed_size_key,
            .value_size = value.len,
            .value = fixed_size_value,
        });
    }
};
