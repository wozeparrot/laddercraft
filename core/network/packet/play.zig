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

// s2c | spawn player packet | 0x04
pub const S2CSpawnPlayerPacket = struct {
    base: *Packet,

    entity_id: i32 = 0,
    uuid: UUID = undefined,
    pos: zlm.Vec3 = zlm.Vec3.zero,
    look: zlm.Vec2 = zlm.Vec2.zero,

    pub fn init(alloc: *Allocator) !*S2CSpawnPlayerPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CSpawnPlayerPacket);
        packet.* = S2CSpawnPlayerPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CSpawnPlayerPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x04;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.entity_id);
        try wr.writeIntBig(u128, self.uuid.uuid);

        try wr.writeIntBig(i64, @bitCast(i64, self.pos.x));
        try wr.writeIntBig(i64, @bitCast(i64, self.pos.y));
        try wr.writeIntBig(i64, @bitCast(i64, self.pos.z));
        try wr.writeIntBig(i8, @floatToInt(i8, self.look.x));
        try wr.writeIntBig(i8, @floatToInt(i8, self.look.y));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CSpawnPlayerPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | entity animation packet | 0x05
pub const S2CEntityAnimationPacket = struct {
    base: *Packet,

    entity_id: i32 = 0,
    animation: u8 = 0,

    pub fn init(alloc: *Allocator) !*S2CEntityAnimationPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityAnimationPacket);
        packet.* = S2CEntityAnimationPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityAnimationPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x05;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.entity_id);
        try wr.writeByte(self.animation);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CEntityAnimationPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | block change packet | 0x0b
pub const S2CBlockChangePacket = struct {
    base: *Packet,

    position: world.block.BlockPos = undefined,
    block_state: world.block.BlockState = 0,

    pub fn init(alloc: *Allocator) !*S2CBlockChangePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CBlockChangePacket);
        packet.* = S2CBlockChangePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CBlockChangePacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x0b;
        self.base.read_write = true;

        var array_list = try std.ArrayList(u8).initCapacity(alloc, 4096);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(i64, @bitCast(i64, self.position.toPacketPosition()));
        try utils.writeVarInt(wr, self.block_state);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CBlockChangePacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player position packet | 0x12
pub const C2SPlayerPositionPacket = struct {
    base: *Packet,

    x: f64,
    y: f64,
    z: f64,
    on_ground: bool,

    pub fn decode(alloc: *Allocator, base: *Packet) !*C2SPlayerPositionPacket {
        const brd = base.toStream().reader();

        const x = @bitCast(f64, try brd.readIntBig(i64));
        const y = @bitCast(f64, try brd.readIntBig(i64));
        const z = @bitCast(f64, try brd.readIntBig(i64));
        const on_ground = if ((try brd.readByte()) == 1) true else false;

        const packet = try alloc.create(C2SPlayerPositionPacket);
        packet.* = C2SPlayerPositionPacket{
            .base = base,

            .x = x,
            .y = y,
            .z = z,
            .on_ground = on_ground,
        };
        return packet;
    }

    pub fn deinit(self: *C2SPlayerPositionPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player position packet | 0x12
pub const C2SPlayerRotationPacket = struct {
    base: *Packet,

    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub fn decode(alloc: *Allocator, base: *Packet) !*C2SPlayerRotationPacket {
        const brd = base.toStream().reader();

        const yaw = @bitCast(f32, try brd.readIntBig(i32));
        const pitch = @bitCast(f32, try brd.readIntBig(i32));
        const on_ground = if ((try brd.readByte()) == 1) true else false;

        const packet = try alloc.create(C2SPlayerRotationPacket);
        packet.* = C2SPlayerRotationPacket{
            .base = base,

            .yaw = yaw,
            .pitch = pitch,
            .on_ground = on_ground,
        };
        return packet;
    }

    pub fn deinit(self: *C2SPlayerRotationPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player digging packet | 0x1b
pub const C2SPlayerDiggingPacket = struct {
    base: *Packet,

    status: i32,

    position: world.block.BlockPos,
    face: i32,

    pub fn decode(alloc: *Allocator, base: *Packet) !*C2SPlayerDiggingPacket {
        const brd = base.toStream().reader();

        const status = try utils.readVarInt(brd);
        
        const position = world.block.BlockPos.fromPacketPosition(try brd.readIntBig(u64));
        const face = try brd.readByte();

        const packet = try alloc.create(C2SPlayerDiggingPacket);
        packet.* = C2SPlayerDiggingPacket{
            .base = base,

            .status = status,

            .position = position,
            .face = face,
        };
        return packet;
    }

    pub fn deinit(self: *C2SPlayerDiggingPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | unload chunk packet | 0x1c
pub const S2CUnloadChunkPacket = struct {
    base: *Packet,

    chunk_x: i32 = 0,
    chunk_z: i32 = 0,

    pub fn init(alloc: *Allocator) !*S2CUnloadChunkPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CUnloadChunkPacket);
        packet.* = S2CUnloadChunkPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CUnloadChunkPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x1c;
        self.base.read_write = true;
        self.base.length = @sizeOf(S2CUnloadChunkPacket) - @sizeOf(usize) + 1;

        var data = try alloc.alloc(u8, @intCast(usize, self.base.length) - 1);
        var strm = std.io.fixedBufferStream(data);
        const wr = strm.writer();

        try wr.writeIntBig(i32, self.chunk_x);
        try wr.writeIntBig(i32, self.chunk_z);

        self.base.data = data;

        return self.base;
    }

    pub fn deinit(self: *S2CUnloadChunkPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

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

    chunk: *world.chunk.Chunk = undefined,
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

        var array_list = try std.ArrayList(u8).initCapacity(alloc, 4096);
        defer array_list.deinit();
        const wr = array_list.writer();

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
        try utils.writeByteArray(wr, cs_data.items);

        try utils.writeVarInt(wr, 0);

        self.base.data = array_list.toOwnedSlice();
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

// s2c | entity position packet | 0x27
pub const S2CEntityPositionPacket = struct {
    base: *Packet,

    entity_id: i32 = 0,
    delta: zlm.Vec3 = zlm.Vec3.zero,
    on_ground: bool = true,

    pub fn init(alloc: *Allocator) !*S2CEntityPositionPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityPositionPacket);
        packet.* = S2CEntityPositionPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityPositionPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x27;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.entity_id);
        try wr.writeIntBig(i16, @floatToInt(i16, self.delta.x));
        try wr.writeIntBig(i16, @floatToInt(i16, self.delta.y));
        try wr.writeIntBig(i16, @floatToInt(i16, self.delta.z));
        try wr.writeByte(@boolToInt(self.on_ground));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CEntityPositionPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | entity rotation packet | 0x29
pub const S2CEntityRotationPacket = struct {
    base: *Packet,

    entity_id: i32 = 0,
    look: zlm.Vec2 = zlm.Vec2.zero,
    on_ground: bool = true,

    pub fn init(alloc: *Allocator) !*S2CEntityRotationPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityRotationPacket);
        packet.* = S2CEntityRotationPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityRotationPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x29;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.entity_id);
        try wr.writeIntBig(i8, @bitCast(i8, @floatToInt(u8, (@mod(self.look.x, 360) / 360) * 256)));
        try wr.writeIntBig(i8, @bitCast(i8, @floatToInt(u8, (@mod(self.look.y, 360) / 360) * 256)));
        try wr.writeByte(@boolToInt(self.on_ground));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CEntityRotationPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | animation packet | 0x2c
pub const C2SAnimationPacket = struct {
    base: *Packet,

    hand: i32,

    pub fn decode(alloc: *Allocator, base: *Packet) !*C2SAnimationPacket {
        const brd = base.toStream().reader();

        const hand = try utils.readVarInt(brd);

        const packet = try alloc.create(C2SAnimationPacket);
        packet.* = C2SAnimationPacket{
            .base = base,

            .hand = hand,
        };
        return packet;
    }

    pub fn deinit(self: *C2SAnimationPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player block placement packet | 0x2e
pub const C2SPlayerBlockPlacementPacket = struct {
    base: *Packet,

    hand: i32,
    
    position: world.block.BlockPos,
    face: i32,

    cursor_x: f32,
    cursor_y: f32,
    cursor_z: f32,

    inside_block: bool,

    pub fn decode(alloc: *Allocator, base: *Packet) !*C2SPlayerBlockPlacementPacket {
        const brd = base.toStream().reader();

        const hand = try utils.readVarInt(brd);
        
        const position = world.block.BlockPos.fromPacketPosition(try brd.readIntBig(u64));
        const face = try utils.readVarInt(brd);

        const cursor_x = @bitCast(f32, try brd.readIntBig(u32));
        const cursor_y = @bitCast(f32, try brd.readIntBig(u32));
        const cursor_z = @bitCast(f32, try brd.readIntBig(u32));

        const inside_block = if ((try brd.readByte()) == 1) true else false;

        const packet = try alloc.create(C2SPlayerBlockPlacementPacket);
        packet.* = C2SPlayerBlockPlacementPacket{
            .base = base,

            .hand = hand,
            
            .position = position,
            .face = face,
            
            .cursor_x = cursor_x,
            .cursor_y = cursor_y,
            .cursor_z = cursor_z,
            
            .inside_block = inside_block,
        };
        return packet;
    }

    pub fn deinit(self: *C2SPlayerBlockPlacementPacket, alloc: *Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | player info packet | 0x32
pub const S2CPlayerInfoAction = enum {
    add_player,
    remove_player,
};
pub const S2CPlayerInfoProperties = struct {
    name: []const u8,
    value: []const u8,
    signature: ?[]const u8,
};
pub const S2CPlayerInfoPlayer = struct {
    uuid: UUID,

    data: union(S2CPlayerInfoAction) {
        add_player: struct {
            name: []const u8,
            properties: []S2CPlayerInfoProperties,
            gamemode: i32,
            ping: i32,
            display_name: ?chat.Text,
        },
        remove_player: void,
    },
};
pub const S2CPlayerInfoPacket = struct {
    base: *Packet,

    action: S2CPlayerInfoAction = undefined,
    players: []S2CPlayerInfoPlayer = undefined,

    pub fn init(alloc: *Allocator) !*S2CPlayerInfoPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CPlayerInfoPacket);
        packet.* = S2CPlayerInfoPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CPlayerInfoPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x32;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, @enumToInt(self.action));

        try utils.writeVarInt(wr, @intCast(i32, self.players.len));
        for (self.players) |player| {
            try wr.writeIntBig(u128, player.uuid.uuid);
            switch (player.data) {
                .add_player => |data| {
                    try utils.writeByteArray(wr, data.name);
                    try utils.writeVarInt(wr, @intCast(i32, data.properties.len));
                    for (data.properties) |prop| {
                        try utils.writeByteArray(wr, prop.name);
                        try utils.writeByteArray(wr, prop.value);
                        if (prop.signature) |sig| {
                            try wr.writeByte(1);
                            try utils.writeByteArray(wr, sig);
                        } else try wr.writeByte(0);
                    }
                    try utils.writeVarInt(wr, data.gamemode);
                    try utils.writeVarInt(wr, data.ping);
                    if (data.display_name) |display_name| {
                        try wr.writeByte(1);
                        try utils.writeJSONStruct(alloc, wr, display_name);
                    } else try wr.writeByte(0);
                },
                .remove_player => {},
            }
        }

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CPlayerInfoPacket, alloc: *Allocator) void {
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

// s2c | entity head look packet | 0x3a
pub const S2CEntityHeadLookPacket = struct {
    base: *Packet,

    entity_id: i32 = 0,
    look: zlm.Vec2 = zlm.Vec2.zero,

    pub fn init(alloc: *Allocator) !*S2CEntityHeadLookPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityHeadLookPacket);
        packet.* = S2CEntityHeadLookPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityHeadLookPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x3a;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.entity_id);
        try wr.writeIntBig(i8, @bitCast(i8, @floatToInt(u8, (@mod(self.look.x, 360) / 360) * 256)));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CEntityHeadLookPacket, alloc: *Allocator) void {
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

// s2c | update view position packet | 0x40
pub const S2CUpdateViewPositionPacket = struct {
    base: *Packet,

    chunk_x: i32 = 0,
    chunk_z: i32 = 0,

    pub fn init(alloc: *Allocator) !*S2CUpdateViewPositionPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CUpdateViewPositionPacket);
        packet.* = S2CUpdateViewPositionPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CUpdateViewPositionPacket, alloc: *Allocator) !*Packet {
        self.base.id = 0x40;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.chunk_x);
        try utils.writeVarInt(wr, self.chunk_z);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CUpdateViewPositionPacket, alloc: *Allocator) void {
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
