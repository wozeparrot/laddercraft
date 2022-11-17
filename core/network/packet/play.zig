const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const io = std.io;
const log = std.log;

const zlm = @import("zlm").SpecializeOn(f64);

const utils = @import("../utils.zig");
const Packet = @import("packet.zig").Packet;
const client = @import("../client/client.zig");
const chat = @import("../../chat/chat.zig");
const UUID = @import("../../uuid.zig").UUID;
const game = @import("../../game/game.zig");
const world = @import("../../world/world.zig");
const nbt = @import("../../nbt/nbt.zig");
const player = @import("../../player/player.zig");

// c2s | chat message packet | 0x05
pub const C2SChatMessagePacket = struct {
    pub const PacketID = 0x05;

    base: *Packet,

    message: []const u8,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SChatMessagePacket {
        const brd = base.toStream().reader();

        const length = try utils.readVarInt(brd);
        const message = try utils.readByteArray(alloc, brd, length);

        const packet = try alloc.create(C2SChatMessagePacket);
        packet.* = C2SChatMessagePacket{
            .base = base,

            .message = message,
        };
        return packet;
    }

    pub fn deinit(self: *C2SChatMessagePacket, alloc: Allocator) void {
        alloc.free(self.message);
        alloc.destroy(self);
    }
};

// s2c | spawn player packet | 0x02
pub const S2CSpawnPlayerPacket = struct {
    pub const PacketID = 0x02;

    base: *Packet,

    entity_id: i32 = 0,
    uuid: UUID = undefined,
    pos: zlm.Vec3 = zlm.Vec3.zero,
    look: zlm.Vec2 = zlm.Vec2.zero,

    pub fn init(alloc: Allocator) !*S2CSpawnPlayerPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CSpawnPlayerPacket);
        packet.* = S2CSpawnPlayerPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CSpawnPlayerPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.entity_id);
        try wr.writeIntBig(u128, self.uuid.uuid);

        try wr.writeIntBig(i64, @bitCast(i64, self.pos.x));
        try wr.writeIntBig(i64, @bitCast(i64, self.pos.y));
        try wr.writeIntBig(i64, @bitCast(i64, self.pos.z));
        try wr.writeIntBig(i8, @bitCast(i8, @floatToInt(u8, (@mod(self.look.x, 360) / 360) * 256)));
        try wr.writeIntBig(i8, @bitCast(i8, @floatToInt(u8, (@mod(self.look.y, 360) / 360) * 256)));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CSpawnPlayerPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | entity animation packet | 0x03
pub const S2CEntityAnimationPacket = struct {
    pub const PacketID = 0x03;

    base: *Packet,

    entity_id: i32 = 0,
    animation: u8 = 0,

    pub fn init(alloc: Allocator) !*S2CEntityAnimationPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityAnimationPacket);
        packet.* = S2CEntityAnimationPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityAnimationPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
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

    pub fn deinit(self: *S2CEntityAnimationPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | block update packet | 0x09
pub const S2CBlockUpdatePacket = struct {
    pub const PacketID = 0x09;

    base: *Packet,

    position: world.block.BlockPos = undefined,
    block_state: world.block.BlockState = 0,

    pub fn init(alloc: Allocator) !*S2CBlockUpdatePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CBlockUpdatePacket);
        packet.* = S2CBlockUpdatePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CBlockUpdatePacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
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

    pub fn deinit(self: *S2CBlockUpdatePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | system chat message packet | 0x62
pub const S2CSystemChatMessagePacket = struct {
    pub const PacketID = 0x62;

    base: *Packet,

    message: chat.Text = undefined,
    overlay: bool = false,

    pub fn init(alloc: Allocator) !*S2CSystemChatMessagePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CSystemChatMessagePacket);
        packet.* = S2CSystemChatMessagePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CSystemChatMessagePacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = try std.ArrayList(u8).initCapacity(alloc, 4096);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeJSONStruct(alloc, wr, self.message);
        try wr.writeByte(@boolToInt(self.overlay));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CSystemChatMessagePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player position packet | 0x14
pub const C2SPlayerPositionPacket = struct {
    pub const PacketID = 0x14;

    base: *Packet,

    x: f64,
    y: f64,
    z: f64,
    on_ground: bool,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SPlayerPositionPacket {
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

    pub fn deinit(self: *C2SPlayerPositionPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player position and rotation packet | 0x15
pub const C2SPlayerPositionRotationPacket = struct {
    pub const PacketID = 0x15;

    base: *Packet,

    x: f64,
    y: f64,
    z: f64,
    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SPlayerPositionRotationPacket {
        const brd = base.toStream().reader();

        const x = @bitCast(f64, try brd.readIntBig(i64));
        const y = @bitCast(f64, try brd.readIntBig(i64));
        const z = @bitCast(f64, try brd.readIntBig(i64));
        const yaw = @bitCast(f32, try brd.readIntBig(i32));
        const pitch = @bitCast(f32, try brd.readIntBig(i32));
        const on_ground = if ((try brd.readByte()) == 1) true else false;

        const packet = try alloc.create(C2SPlayerPositionRotationPacket);
        packet.* = C2SPlayerPositionRotationPacket{
            .base = base,

            .x = x,
            .y = y,
            .z = z,
            .yaw = yaw,
            .pitch = pitch,
            .on_ground = on_ground,
        };
        return packet;
    }

    pub fn deinit(self: *C2SPlayerPositionRotationPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player rotation packet | 0x16
pub const C2SPlayerRotationPacket = struct {
    pub const PacketID = 0x16;

    base: *Packet,

    yaw: f32,
    pitch: f32,
    on_ground: bool,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SPlayerRotationPacket {
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

    pub fn deinit(self: *C2SPlayerRotationPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player action packet | 0x1d
pub const C2SPlayerActionPacket = struct {
    pub const PacketID = 0x1d;

    base: *Packet,

    status: i32,

    position: world.block.BlockPos,
    face: i32,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SPlayerActionPacket {
        const brd = base.toStream().reader();

        const status = try utils.readVarInt(brd);

        const position = world.block.BlockPos.fromPacketPosition(try brd.readIntBig(u64));
        const face = try brd.readByte();

        const packet = try alloc.create(C2SPlayerActionPacket);
        packet.* = C2SPlayerActionPacket{
            .base = base,

            .status = status,

            .position = position,
            .face = face,
        };
        return packet;
    }

    pub fn deinit(self: *C2SPlayerActionPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | unload chunk packet | 0x1c
pub const S2CUnloadChunkPacket = struct {
    pub const PacketID = 0x1c;

    base: *Packet,

    chunk_x: i32 = 0,
    chunk_z: i32 = 0,

    pub fn init(alloc: Allocator) !*S2CUnloadChunkPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CUnloadChunkPacket);
        packet.* = S2CUnloadChunkPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CUnloadChunkPacket, alloc: Allocator) !*Packet {
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

    pub fn deinit(self: *S2CUnloadChunkPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | keep alive packet | 0x20
pub const S2CKeepAlivePacket = struct {
    pub const PacketID = 0x20;

    base: *Packet,

    id: u64 = 0,

    pub fn init(alloc: Allocator) !*S2CKeepAlivePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CKeepAlivePacket);
        packet.* = S2CKeepAlivePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CKeepAlivePacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;
        self.base.length = @sizeOf(S2CKeepAlivePacket) - @sizeOf(usize) + 1;

        var data = try alloc.alloc(u8, @intCast(usize, self.base.length) - 1);
        var strm = std.io.fixedBufferStream(data);
        const wr = strm.writer();

        try wr.writeIntBig(u64, self.id);

        self.base.data = data;

        return self.base;
    }

    pub fn deinit(self: *S2CKeepAlivePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | chunk data packet | 0x21
pub const S2CChunkDataPacket = struct {
    pub const PacketID = 0x21;

    base: *Packet,

    chunk: *world.chunk.Chunk = undefined,

    pub fn init(alloc: Allocator) !*S2CChunkDataPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CChunkDataPacket);
        packet.* = S2CChunkDataPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CChunkDataPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = try std.ArrayList(u8).initCapacity(alloc, 4096);
        defer array_list.deinit();
        const wr = array_list.writer();

        // chunk pos
        try wr.writeIntBig(i32, self.chunk.x);
        try wr.writeIntBig(i32, self.chunk.z);

        // heightmaps
        var heightmap_data_array = try world.chunk.CompactedDataArray.init(alloc, 9, 256);
        defer heightmap_data_array.deinit(alloc);
        var x: u32 = 0;
        while (x < 16) : (x += 1) {
            var z: u32 = 0;
            while (z < 16) : (z += 1) {
                heightmap_data_array.set((x * 16) + z, self.chunk.getHighestBlock(x, z));
            }
        }
        const heightmap_nbt = nbt.Tag{
            .compound = .{
                .name = "",
                .payload = &[_]nbt.Tag{
                    .{
                        .long_array = .{
                            .name = "MOTION_BLOCKING",
                            .payload = @ptrCast([*]i64, heightmap_data_array.data.ptr)[0..36],
                        },
                    },
                },
            },
        };
        try nbt.writeTag(wr, heightmap_nbt, false);

        // chunk sections
        var cs_data = std.ArrayList(u8).init(alloc);
        defer cs_data.deinit();
        var cs_wr = cs_data.writer();
        for (self.chunk.sections.values()) |section| {
            try cs_wr.writeIntBig(i16, @intCast(i16, section.block_count));

            try cs_wr.writeByte(section.data.element_bits);
            try utils.writeVarInt(cs_wr, @intCast(i32, section.data.data.len));
            for (section.data.data) |long| {
                try cs_wr.writeIntBig(i64, @bitCast(i64, long));
            }

            try cs_wr.writeByte(0);
            try utils.writeVarInt(cs_wr, 0);
            try utils.writeVarInt(cs_wr, 0);
        }
        try utils.writeByteArray(wr, cs_data.items);

        // block entities
        try utils.writeVarInt(wr, 0);

        // trust edges
        try wr.writeByte(@boolToInt(true));

        // TODO: handle bitsets
        try utils.writeVarInt(wr, 0);
        try utils.writeVarInt(wr, 0);
        try utils.writeVarInt(wr, 1);
        try wr.writeIntBig(i64, 0x3FFFF);
        try utils.writeVarInt(wr, 1);
        try wr.writeIntBig(i64, 0x3FFFF);

        // sky light array
        try utils.writeVarInt(wr, 0);

        // block light array
        try utils.writeVarInt(wr, 0);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CChunkDataPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | join game packet | 0x25
pub const S2CJoinGamePacket = struct {
    pub const PacketID = 0x25;
    base: *Packet,

    entity_id: i32 = 0,
    gamemode: game.Gamemode = .{ .mode = .survival, .hardcore = false },
    previous_gamemode: i8 = -1,
    dimensions: []const []const u8 = &[_][]const u8{"minecraft:world"},
    registry_codec: nbt.Tag = undefined,
    dimension_type: []const u8 = "minecraft:overworld",
    dimension_name: []const u8 = "minecraft:world",
    hashed_seed: u64 = 0,
    view_distance: u8 = 8,
    simulation_distace: u8 = 8,
    gamerules: game.Gamerules = .{},
    is_debug: bool = false,
    is_flat: bool = false,

    pub fn init(alloc: Allocator) !*S2CJoinGamePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CJoinGamePacket);
        packet.* = S2CJoinGamePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CJoinGamePacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        // entity id
        try wr.writeIntBig(i32, self.entity_id);

        // gamemode
        try wr.writeByte(@boolToInt(self.gamemode.hardcore));
        try wr.writeByte(@enumToInt(self.gamemode.mode));
        try wr.writeIntBig(i8, self.previous_gamemode);

        // dimensions
        try utils.writeVarInt(wr, @intCast(i32, self.dimensions.len));
        for (self.dimensions) |d| try utils.writeByteArray(wr, d);

        //registry codec
        try nbt.writeTag(wr, self.registry_codec, false);

        // dimensions type
        try utils.writeByteArray(wr, self.dimension_type);

        // dimension name
        try utils.writeByteArray(wr, self.dimension_name);

        // hashed seed
        try wr.writeIntBig(u64, self.hashed_seed);

        // max players
        try wr.writeByte(0);

        // view distance
        try utils.writeVarInt(wr, self.view_distance);

        // simulation distance
        try utils.writeVarInt(wr, self.simulation_distace);

        // gamerules
        try wr.writeByte(@boolToInt(self.gamerules.reduced_debug_info));
        try wr.writeByte(@boolToInt(self.gamerules.do_immediate_respawn));

        // is debug
        try wr.writeByte(@boolToInt(self.is_debug));

        // is flat
        try wr.writeByte(@boolToInt(self.is_flat));

        // TODO: handle death location
        try wr.writeByte(@boolToInt(false));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CJoinGamePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | held item change packet | 0x28
pub const C2SHeldItemChangePacket = struct {
    pub const PacketID = 0x28;

    base: *Packet,

    slot: u8,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SHeldItemChangePacket {
        const brd = base.toStream().reader();

        const slot = @intCast(u8, try brd.readIntBig(i16));

        const packet = try alloc.create(C2SHeldItemChangePacket);
        packet.* = C2SHeldItemChangePacket{
            .base = base,

            .slot = slot,
        };
        return packet;
    }

    pub fn deinit(self: *C2SHeldItemChangePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | entity position packet | 0x28
pub const S2CEntityPositionPacket = struct {
    pub const PacketID = 0x28;

    base: *Packet,

    entity_id: i32 = 0,
    delta: zlm.Vec3 = zlm.Vec3.zero,
    on_ground: bool = true,

    pub fn init(alloc: Allocator) !*S2CEntityPositionPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityPositionPacket);
        packet.* = S2CEntityPositionPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityPositionPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
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

    pub fn deinit(self: *S2CEntityPositionPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | entity position and rotation packet | 0x29
pub const S2CEntityPositionRotationPacket = struct {
    pub const PacketID = 0x29;

    base: *Packet,

    entity_id: i32 = 0,
    delta: zlm.Vec3 = zlm.Vec3.zero,
    look: zlm.Vec2 = zlm.Vec2.zero,
    on_ground: bool = true,

    pub fn init(alloc: Allocator) !*S2CEntityPositionRotationPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityPositionRotationPacket);
        packet.* = S2CEntityPositionRotationPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityPositionRotationPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, self.entity_id);
        try wr.writeIntBig(i16, @floatToInt(i16, self.delta.x));
        try wr.writeIntBig(i16, @floatToInt(i16, self.delta.y));
        try wr.writeIntBig(i16, @floatToInt(i16, self.delta.z));
        try wr.writeIntBig(i8, @bitCast(i8, @floatToInt(u8, (@mod(self.look.x, 360) / 360) * 256)));
        try wr.writeIntBig(i8, @bitCast(i8, @floatToInt(u8, (@mod(self.look.y, 360) / 360) * 256)));
        try wr.writeByte(@boolToInt(self.on_ground));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CEntityPositionRotationPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | entity rotation packet | 0x2a
pub const S2CEntityRotationPacket = struct {
    pub const PacketID = 0x2a;

    base: *Packet,

    entity_id: i32 = 0,
    look: zlm.Vec2 = zlm.Vec2.zero,
    on_ground: bool = true,

    pub fn init(alloc: Allocator) !*S2CEntityRotationPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityRotationPacket);
        packet.* = S2CEntityRotationPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityRotationPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
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

    pub fn deinit(self: *S2CEntityRotationPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | creative inventory packet | 0x2b
pub const C2SCreativeInventoryActionPacket = struct {
    pub const PacketID = 0x2b;

    base: *Packet,

    slot: i16,
    clicked_item: ?player.inventory.Slot,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SCreativeInventoryActionPacket {
        const brd = base.toStream().reader();

        const slot = try brd.readIntBig(i16);
        const clicked_item = if ((try brd.readByte()) == 1) player.inventory.Slot{
            .id = try utils.readVarInt(brd),
            .count = try brd.readByte(),
            // TODO: nbt parsing
        } else null;

        const packet = try alloc.create(C2SCreativeInventoryActionPacket);
        packet.* = C2SCreativeInventoryActionPacket{
            .base = base,

            .slot = slot,
            .clicked_item = clicked_item,
        };
        return packet;
    }

    pub fn deinit(self: *C2SCreativeInventoryActionPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | swing hand packet | 0x2f
pub const C2SSwingHandPacket = struct {
    pub const PacketID = 0x2f;

    base: *Packet,

    hand: i32,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SSwingHandPacket {
        const brd = base.toStream().reader();

        const hand = try utils.readVarInt(brd);

        const packet = try alloc.create(C2SSwingHandPacket);
        packet.* = C2SSwingHandPacket{
            .base = base,

            .hand = hand,
        };
        return packet;
    }

    pub fn deinit(self: *C2SSwingHandPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | player use item on packet | 0x31
pub const C2SPlayerUseItemOnPacket = struct {
    pub const PacketID = 0x31;

    base: *Packet,

    hand: i32,

    position: world.block.BlockPos,
    face: i32,

    cursor_x: f32,
    cursor_y: f32,
    cursor_z: f32,

    inside_block: bool,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SPlayerUseItemOnPacket {
        const brd = base.toStream().reader();

        const hand = try utils.readVarInt(brd);

        const position = world.block.BlockPos.fromPacketPosition(try brd.readIntBig(u64));
        const face = try utils.readVarInt(brd);

        const cursor_x = @bitCast(f32, try brd.readIntBig(u32));
        const cursor_y = @bitCast(f32, try brd.readIntBig(u32));
        const cursor_z = @bitCast(f32, try brd.readIntBig(u32));

        const inside_block = if ((try brd.readByte()) == 1) true else false;

        const packet = try alloc.create(C2SPlayerUseItemOnPacket);
        packet.* = C2SPlayerUseItemOnPacket{
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

    pub fn deinit(self: *C2SPlayerUseItemOnPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | player info packet | 0x37
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
    pub const PacketID = 0x37;

    base: *Packet,

    action: S2CPlayerInfoAction = undefined,
    players: []S2CPlayerInfoPlayer = undefined,

    pub fn init(alloc: Allocator) !*S2CPlayerInfoPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CPlayerInfoPacket);
        packet.* = S2CPlayerInfoPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CPlayerInfoPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeVarInt(wr, @enumToInt(self.action));

        try utils.writeVarInt(wr, @intCast(i32, self.players.len));
        for (self.players) |p| {
            try wr.writeIntBig(u128, p.uuid.uuid);

            std.debug.assert(self.action == p.data);
            switch (p.data) {
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

                    try wr.writeByte(@boolToInt(false));
                },
                .remove_player => {},
            }
        }

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CPlayerInfoPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | player position look packet | 0x39
pub const S2CPlayerPositionLookPacket = struct {
    pub const PacketID = 0x39;

    base: *Packet,

    pos: zlm.Vec3 = zlm.Vec3.zero,
    look: zlm.Vec2 = zlm.Vec2.zero,
    flags: packed struct {
        x: bool = false,
        y: bool = false,
        z: bool = false,
        yaw: bool = false,
        pitch: bool = false,

        __pad: u3 = 0,
    } = .{},
    teleport_id: i32 = 0,
    dismount_vehicle: bool = false,

    pub fn init(alloc: Allocator) !*S2CPlayerPositionLookPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CPlayerPositionLookPacket);
        packet.* = S2CPlayerPositionLookPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CPlayerPositionLookPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(u64, @bitCast(u64, self.pos.x));
        try wr.writeIntBig(u64, @bitCast(u64, self.pos.y));
        try wr.writeIntBig(u64, @bitCast(u64, self.pos.z));

        try wr.writeIntBig(i32, @floatToInt(i32, self.look.y));
        try wr.writeIntBig(i32, @floatToInt(i32, self.look.x));

        try wr.writeByte(@bitCast(u8, self.flags));

        try utils.writeVarInt(wr, self.teleport_id);

        try wr.writeByte(@boolToInt(self.dismount_vehicle));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CPlayerPositionLookPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | entity head look packet | 0x3f
pub const S2CEntityHeadLookPacket = struct {
    pub const PacketID = 0x3f;

    base: *Packet,

    entity_id: i32 = 0,
    look: zlm.Vec2 = zlm.Vec2.zero,

    pub fn init(alloc: Allocator) !*S2CEntityHeadLookPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CEntityHeadLookPacket);
        packet.* = S2CEntityHeadLookPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CEntityHeadLookPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
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

    pub fn deinit(self: *S2CEntityHeadLookPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | held item change packet | 0x4a
pub const S2CHeldItemChangePacket = struct {
    pub const PacketID = 0x4a;

    base: *Packet,

    slot: u8 = 0,

    pub fn init(alloc: Allocator) !*S2CHeldItemChangePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CHeldItemChangePacket);
        packet.* = S2CHeldItemChangePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CHeldItemChangePacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeByte(self.slot);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CHeldItemChangePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | update view position packet | 0x4b
pub const S2CUpdateViewPositionPacket = struct {
    pub const PacketID = 0x4b;

    base: *Packet,

    chunk_x: i32 = 0,
    chunk_z: i32 = 0,

    pub fn init(alloc: Allocator) !*S2CUpdateViewPositionPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CUpdateViewPositionPacket);
        packet.* = S2CUpdateViewPositionPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CUpdateViewPositionPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
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

    pub fn deinit(self: *S2CUpdateViewPositionPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | spawn position packet | 0x4d
pub const S2CSpawnPositionPacket = struct {
    pub const PacketID = 0x4d;

    base: *Packet,

    pos: zlm.Vec3 = zlm.Vec3.zero,
    angle: f32 = 0,

    pub fn init(alloc: Allocator) !*S2CSpawnPositionPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CSpawnPositionPacket);
        packet.* = S2CSpawnPositionPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CSpawnPositionPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(u64, utils.toPacketPosition(self.pos));
        try wr.writeIntBig(i32, @bitCast(i32, self.angle));

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CSpawnPositionPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};
