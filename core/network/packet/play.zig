const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const io = std.io;
const log = std.log;

const utils = @import("../utils.zig");

const Packet = @import("packet.zig").Packet;

const client = @import("../client/client.zig");
const chat = @import("../../chat/chat.zig");
const UUID = @import("../../uuid.zig").UUID;
const game = @import("../../game/game.zig");
const world = @import("../../world/world.zig");

// s2c | join game packet | 0x24
pub const S2CJoinGamePacket = struct {
    base: *Packet,

    entity_id: i32 = 0,
    gamemode: game.Gamemode = .{ .mode = .survival, .hardcore = false },
    previous_gamemode: i8 = -1,
    worlds: []const []const u8 = &[_][]const u8{"world"},
    dimension: i32 = 0,
    world_name: []const u8 = "world",
    hashed_seed: u64 = 0,
    view_distance: u8 = 2,
    gamerules: game.Gamerules = .{},
    is_debug: bool = false,
    is_flat: bool = false,

    pub fn init(alloc: *Allocator) !*S2CJoinGamePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CJoinGamePacket);
        packet.* = S2CJoinGamePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CJoinGamePacket, alloc: *Allocator, writer: anytype) !void {
        self.base.id = 0x25;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(i32, self.entity_id);
        try wr.writeIntBig(u8, @boolToInt(self.gamemode.hardcore));
        try wr.writeByte(@enumToInt(self.gamemode.mode));
        try wr.writeIntBig(i8, self.previous_gamemode);
        try utils.writeVarInt(wr, @intCast(i32, self.worlds.len));
        for (self.worlds) |w| try utils.writeByteArray(wr, w);
        
        try wr.writeByte(10);
        try wr.writeByte(0);
        try wr.writeByte(10);
        try wr.writeByte(0);

        try utils.writeByteArray(wr, self.world_name);
        try wr.writeIntBig(u64, self.hashed_seed);
        try wr.writeByte(0);
        try utils.writeVarInt(wr, self.view_distance);
        try wr.writeByte(@boolToInt(self.gamerules.reduced_debug_info));
        try wr.writeByte(@boolToInt(self.gamerules.do_immediate_respawn));
        try wr.writeByte(@boolToInt(self.is_debug));
        try wr.writeByte(@boolToInt(self.is_flat));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        try self.base.encode(alloc, writer);
    }

    pub fn deinit(self: *S2CJoinGamePacket, alloc: *Allocator) void {
        self.base.deinit(alloc);
        alloc.destroy(self);
    }
};
