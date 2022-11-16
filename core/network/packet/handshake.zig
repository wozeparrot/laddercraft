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

// c2s | handshake packet | 0x00
pub const C2SHandshakePacket = struct {
    pub const PacketID = 0x00;

    base: *Packet,

    protocol_version: i32,
    server_address: []const u8,
    server_port: u16,
    next_state: client.ConnectionState,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SHandshakePacket {
        const brd = base.toStream().reader();

        const protocol_version = try utils.readVarInt(brd);
        const server_address = try utils.readByteArray(alloc, brd, try utils.readVarInt(brd));
        const server_port = try brd.readIntBig(u16);
        const next_state = @intToEnum(client.ConnectionState, try brd.readIntBig(u8));

        const packet = try alloc.create(C2SHandshakePacket);
        packet.* = C2SHandshakePacket{
            .base = base,

            .protocol_version = protocol_version,
            .server_address = server_address,
            .server_port = server_port,
            .next_state = next_state,
        };
        return packet;
    }

    pub fn deinit(self: *C2SHandshakePacket, alloc: Allocator) void {
        alloc.free(self.server_address);
        alloc.destroy(self);
    }
};

// c2s | login start packet | 0x00
pub const C2SLoginStartPacket = struct {
    pub const PacketID = 0x00;

    base: *Packet,

    username: []const u8,

    has_sig_data: bool,
    timestamp: ?i64,
    public_key_length: ?i32,
    public_key: ?[]const u8,
    signature_length: ?i32,
    signature: ?[]const u8,

    has_player_uuid: bool,
    uuid: ?UUID,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SLoginStartPacket {
        const brd = base.toStream().reader();

        const username = try utils.readByteArray(alloc, brd, try utils.readVarInt(brd));
        const has_sig_data = if ((try brd.readByte()) == 1) true else false;
        var timestamp: ?i64 = null;
        var public_key_length: ?i32 = null;
        var public_key: ?[]const u8 = null;
        var signature_length: ?i32 = null;
        var signature: ?[]const u8 = null;
        if (has_sig_data) {
            timestamp = try brd.readIntBig(i64);
            public_key_length = try utils.readVarInt(brd);
            public_key = try utils.readByteArray(alloc, brd, public_key_length.?);
            signature_length = try utils.readVarInt(brd);
            signature = try utils.readByteArray(alloc, brd, signature_length.?);
        }

        const has_player_uuid = if ((try brd.readByte()) == 1) true else false;
        var uuid: ?UUID = null;
        if (has_player_uuid) {
            uuid = UUID{
                .version = .v4,
                .uuid = try brd.readIntBig(u128),
            };
        }

        const packet = try alloc.create(C2SLoginStartPacket);
        packet.* = C2SLoginStartPacket{
            .base = base,

            .username = username,

            .has_sig_data = has_sig_data,
            .timestamp = timestamp,
            .public_key_length = public_key_length,
            .public_key = public_key,
            .signature_length = signature_length,
            .signature = signature,

            .has_player_uuid = has_player_uuid,
            .uuid = uuid,
        };
        return packet;
    }

    pub fn deinit(self: *C2SLoginStartPacket, alloc: Allocator) void {
        alloc.free(self.username);
        if (self.has_sig_data) {
            alloc.free(self.public_key.?);
            alloc.free(self.signature.?);
        }
        alloc.destroy(self);
    }
};

// s2c | login success packet | 0x02
pub const S2CLoginSuccessPacket = struct {
    pub const PacketID = 0x02;

    base: *Packet,

    uuid: UUID = undefined,
    username: []const u8 = undefined,

    pub fn init(alloc: Allocator) !*S2CLoginSuccessPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CLoginSuccessPacket);
        packet.* = S2CLoginSuccessPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CLoginSuccessPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(u128, self.uuid.uuid);
        try utils.writeByteArray(wr, self.username);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CLoginSuccessPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | login disconnect packet | 0x00
pub const S2CLoginDisconnectPacket = struct {
    pub const PacketID = 0x00;

    base: *Packet,

    reason: chat.Text = undefined,

    pub fn init(alloc: Allocator) !*S2CLoginDisconnectPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CLoginDisconnectPacket);
        packet.* = S2CLoginDisconnectPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CLoginDisconnectPacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeJSONStruct(alloc, wr, self.reason);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CLoginDisconnectPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | status response packet | 0x00
pub const S2CStatusResponsePacket = struct {
    pub const PacketID = 0x00;

    base: *Packet,

    response: []const u8 = undefined,

    pub fn init(alloc: Allocator) !*S2CStatusResponsePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CStatusResponsePacket);
        packet.* = S2CStatusResponsePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CStatusResponsePacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeByteArray(wr, self.response);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CStatusResponsePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// c2s | ping request packet | 0x01
pub const C2SPingRequestPacket = struct {
    pub const PacketID = 0x01;

    base: *Packet,

    payload: i64,

    pub fn decode(alloc: Allocator, base: *Packet) !*C2SPingRequestPacket {
        const brd = base.toStream().reader();

        const payload = try brd.readIntBig(i64);

        const packet = try alloc.create(C2SPingRequestPacket);
        packet.* = C2SPingRequestPacket{
            .base = base,

            .payload = payload,
        };
        return packet;
    }

    pub fn deinit(self: *C2SPingRequestPacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};

// s2c | ping response packet | 0x01
pub const S2CPingResponsePacket = struct {
    pub const PacketID = 0x01;

    base: *Packet,

    payload: i64 = undefined,

    pub fn init(alloc: Allocator) !*S2CPingResponsePacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CPingResponsePacket);
        packet.* = S2CPingResponsePacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CPingResponsePacket, alloc: Allocator) !*Packet {
        self.base.id = PacketID;
        self.base.read_write = true;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(i64, self.payload);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        return self.base;
    }

    pub fn deinit(self: *S2CPingResponsePacket, alloc: Allocator) void {
        alloc.destroy(self);
    }
};
