const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const io = std.io;
const log = std.log;

const zlm = @import("zlm").specializeOn(f64);

const utils = @import("../utils.zig");
const Packet = @import("packet.zig").Packet;
const client = @import("../client/client.zig");
const chat = @import("../../chat/chat.zig");
const UUID = @import("../../uuid.zig").UUID;
const game = @import("../../game/game.zig");
const world = @import("../../world/world.zig");
const nbt = @import("../../nbt/nbt.zig");

// s2c | keep alive packet | 0x1f
pub const S2CKeepAlivePacket = struct {
    base: *Packet,

    id: u64 = 0,

    pub fn init(alloc: *Allocator) !*S2CKeepAlivePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CKeepAlivePacket);
        packet.* = S2CKeepAlivePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CKeepAlivePacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x1f;
        self.base.read_write = true;
        self.base.length = @sizeOf(S2CKeepAlivePacket) - @sizeOf(usize) + 1;

        var data = try alloc.alloc(u8, @intCast(usize, self.base.length) - 1);
        var strm = std.io.fixedBufferStream(data);
        const wr = strm.writer();

        try wr.writeIntBig(u64, self.id);

        self.base.data = data;

        return self.base;
    }

    pub fn deinit(self: *S2CKeepAlivePacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | chunk data packet | 0x20
pub const S2CChunkDataPacket = struct {
    base: *Packet,

    chunk: world.chunk.Chunk = undefined,
    full_chunk: bool = true,

    pub fn init(alloc: *Allocator) !*S2CChunkDataPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CChunkDataPacket);
        packet.* = S2CChunkDataPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CChunkDataPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x20;
        self.base.read_write = true;

        var buf = try alloc.alloc(u8, 2097151);
        var strm = std.io.fixedBufferStream(buf);
        const wr = strm.writer();

        try wr.writeIntBig(i32, self.chunk.x);
        try wr.writeIntBig(i32, self.chunk.z);

        try wr.writeByte(@boolToInt(self.full_chunk));

        var bitmask: u32 = 0;
        for (self.chunk.sections.items()) |section| {
            bitmask |= @as(u32, 1) << @intCast(u5, section.key);
        }
        try utils.writeVarInt(wr, @bitCast(i32, bitmask));

        var heightmap_data_array = try world.chunk.CompactedDataArray.init(alloc, 9, 256);
        defer heightmap_data_array.deinit(alloc);
        var z: u32 = 0;
        while (z < 16) : (z += 1) {
            var x: u32 = 0;
            while (x < 16) : (x += 1) {
                heightmap_data_array.set((z * 16) + x, self.chunk.getHighestBlockSection(@intCast(u32, x), @intCast(u32, z)));
            }
        }
        var heightmap_nbt = nbt.Tag{
            .compound = .{
                .name = "",
                .payload = &[_]nbt.Tag{
                    .{ .long_array = .{
                        .name = "MOTION_BLOCKING",
                        .payload = @ptrCast([*]i64, heightmap_data_array.data.ptr)[0..36],
                    }},
                },
            },
        };
        try nbt.writeTag(wr, heightmap_nbt, false);

        try utils.writeByteArray(wr, &[_]u8{0} ** 1024);

        var cs_data = std.ArrayList(u8).init(alloc);
        defer cs_data.deinit();
        var cs_wr = cs_data.writer();
        for (self.chunk.sections.items()) |entry| {
            const section = entry.value;
            try cs_wr.writeIntBig(i16, @intCast(i16, section.block_count));
            try cs_wr.writeByte(section.data.element_bits);
            try utils.writeVarInt(cs_wr, @intCast(i32, section.data.data.len));
            for (section.data.data) |long| {
                try cs_wr.writeIntBig(i64, @bitCast(i64, long));
            }
        }
        try utils.writeByteArray(wr, cs_data.toOwnedSlice());

        try utils.writeVarInt(wr, 0);

        self.base.data = alloc.shrink(buf, strm.pos);
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CChunkDataPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | join game packet | 0x24
pub const S2CJoinGamePacket = struct {
    base: *Packet,

    entity_id: i32 = 0,
    gamemode: game.Gamemode = .{ .mode = .survival, .hardcore = false },
    previous_gamemode: i8 = -1,
    worlds: []const []const u8 = &[_][]const u8{"world"},
    dimension_codec: nbt.Tag = undefined,
    dimension: nbt.Tag = undefined,
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

    pub fn encode(self: *S2CJoinGamePacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x24;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(i32, self.entity_id);

        try wr.writeByte(@boolToInt(self.gamemode.hardcore));
        try wr.writeByte(@enumToInt(self.gamemode.mode));
        try wr.writeIntBig(i8, self.previous_gamemode);

        try utils.writeVarInt(wr, @intCast(i32, self.worlds.len));
        for (self.worlds) |w| try utils.writeByteArray(wr, w);

        try nbt.writeTag(wr, self.dimension_codec, false);
        try nbt.writeTag(wr, self.dimension, false);

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

        return self.base;
    }

    pub fn deinit(self: *S2CJoinGamePacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | player position look packet | 0x34
pub const S2CPlayerPositionLookPacket = struct {
    base: *Packet,

    pos: zlm.Vec3 = zlm.Vec3.zero,
    look: zlm.Vec2 = zlm.Vec2.zero,
    flags: u8 = 0,
    teleport_id: i32 = 0,

    pub fn init(alloc: *Allocator) !*S2CPlayerPositionLookPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CPlayerPositionLookPacket);
        packet.* = S2CPlayerPositionLookPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CPlayerPositionLookPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x34;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(u64, @bitCast(u64, self.pos.x));
        try wr.writeIntBig(u64, @bitCast(u64, self.pos.y));
        try wr.writeIntBig(u64, @bitCast(u64, self.pos.z));

        try wr.writeIntBig(i32, @floatToInt(i32, self.look.y));
        try wr.writeIntBig(i32, @floatToInt(i32, self.look.x));

        try wr.writeByte(self.flags);

        try utils.writeVarInt(wr, self.teleport_id);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CPlayerPositionLookPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | held item change packet | 0x3f
pub const S2CHeldItemChangePacket = struct {
    base: *Packet,

    slot: u8 = 0,

    pub fn init(alloc: *Allocator) !*S2CHeldItemChangePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CHeldItemChangePacket);
        packet.* = S2CHeldItemChangePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CHeldItemChangePacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x3f;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeByte(self.slot);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CHeldItemChangePacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | spawn position packet | 0x42
pub const S2CSpawnPositionPacket = struct {
    base: *Packet,

    pos: zlm.Vec3 = zlm.Vec3.zero,

    pub fn init(alloc: *Allocator) !*S2CSpawnPositionPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CSpawnPositionPacket);
        packet.* = S2CSpawnPositionPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CSpawnPositionPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x42;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(u64, utils.toPacketPosition(self.pos));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CSpawnPositionPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};
