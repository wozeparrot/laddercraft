const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const io = std.io;
const log = std.log;

const utils = @import("../utils.zig");

const client = @import("../client/client.zig");
const chat = @import("../../chat/chat.zig");
const UUID = @import("../../uuid.zig").UUID;

pub usingnamespace @import("handshake.zig");
pub usingnamespace @import("play.zig");

/// generic packet
/// s2c packets do not own the data
/// c2s packets own the data
pub const Packet = struct {
    length: i32,
    id: u8,
    data: []u8,

    // false when reading, true when writing
    read_write: bool,
    raw_data: []u8,

    pub fn init(alloc: *Allocator) !*Packet {
        const packet = try alloc.create(Packet);
        packet.* = .{
            .length = 0,
            .id = 0xFF,
            .data = undefined,

            .read_write = false,
            .raw_data = undefined,
        };
        return packet;
    }

    pub fn encode(self: *Packet, alloc: *Allocator, wr: anytype) !void {
        try utils.writeVarInt(wr, self.length);
        try wr.writeByte(self.id);
        try wr.writeAll(self.data);
    }

    pub fn decode(alloc: *Allocator, rd: anytype) !*Packet {
        const length = try utils.readVarInt(rd);
        const data = try utils.readByteArray(alloc, rd, length);
        const id = data[0];

        const packet = try alloc.create(Packet);
        packet.* = .{
            .length = length,
            .id = id,
            .data = data[1..],

            .read_write = false,
            .raw_data = data,
        };
        return packet;
    }

    pub fn deinit(self: *Packet, alloc: *Allocator) void {
        if (!self.read_write) {
            if (self.id != 0xFF) alloc.free(self.raw_data);
        } else {
            if (self.id != 0xFF) alloc.free(self.data);
        }
        alloc.destroy(self);
    }

    pub fn copy(self: *Packet, alloc: *Allocator) !*Packet {
        const data = if (self.read_write) try alloc.dupe(u8, self.data) else try alloc.dupe(u8, self.raw_data);

        const packet = try alloc.create(Packet);
        packet.* = .{
            .length = self.length,
            .id = self.id,
            .data = if (self.read_write) data else data[1..],

            .read_write = self.read_write,
            .raw_data = if (self.read_write) undefined else data,
        };
        return packet;
    }

    pub fn toStream(self: *Packet) io.FixedBufferStream([]u8) {
        return io.fixedBufferStream(self.data);
    }

    pub fn format(self: *const Packet, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try std.fmt.format(writer, "Packet{{{}, 0x{x}}}", .{ self.length, self.id });
    }
};
