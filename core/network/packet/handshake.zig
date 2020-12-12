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
    base: *Packet,

    protocol_version: i32,
    server_address: []const u8,
    server_port: u16,
    next_state: client.ConnectionState,

    pub fn decode(alloc: *Allocator, rd: anytype) !*C2SHandshakePacket {
        const base = Packet.decode(alloc, rd);
        return decodeBase(alloc, base);
    }

    pub fn decodeBase(alloc: *Allocator, base: *Packet) !*C2SHandshakePacket {
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

    pub fn deinit(self: *C2SHandshakePacket, alloc: *Allocator) void {
        alloc.free(self.server_address);
        self.base.deinit(alloc);
        alloc.destroy(self);
    }
};

// c2s | login start packet | 0x00
pub const C2SLoginStartPacket = struct {
    base: *Packet,

    username: []const u8,

    pub fn decode(alloc: *Allocator, rd: anytype) !*C2SLoginStartPacket {
        const base = Packet.decode(alloc, rd);
        return decodeBase(alloc, base);
    }

    pub fn decodeBase(alloc: *Allocator, base: *Packet) !*C2SLoginStartPacket {
        const brd = base.toStream().reader();

        const username = try utils.readByteArray(alloc, brd, try utils.readVarInt(brd));

        const packet = try alloc.create(C2SLoginStartPacket);
        packet.* = C2SLoginStartPacket{
            .base = base,

            .username = username,
        };
        return packet;
    }

    pub fn deinit(self: *C2SLoginStartPacket, alloc: *Allocator) void {
        alloc.free(self.username);
        self.base.deinit(alloc);
        alloc.destroy(self);
    }
};

// s2c | login success packet | 0x02
pub const S2CLoginSuccessPacket = struct {
    base: *Packet,

    uuid: UUID = undefined,
    username: []const u8 = undefined,

    pub fn init(alloc: *Allocator) !*S2CLoginSuccessPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CLoginSuccessPacket);
        packet.* = S2CLoginSuccessPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CLoginSuccessPacket, alloc: *Allocator, writer: anytype) !void {
        self.base.id = 0x02;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try wr.writeIntBig(u128, self.uuid.uuid);
        try utils.writeByteArray(wr, self.username);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        try self.base.encode(alloc, writer);
    }

    pub fn deinit(self: *S2CLoginSuccessPacket, alloc: *Allocator) void {
        self.base.deinit(alloc);
        alloc.destroy(self);
    }
};

// s2c | login disconnect packet | 0x00
pub const S2CLoginDisconnectPacket = struct {
    base: *Packet,

    reason: chat.Text = undefined,

    pub fn init(alloc: *Allocator) !*S2CLoginDisconnectPacket {
        const base = try Packet.init(alloc);

        const packet = try alloc.create(S2CLoginDisconnectPacket);
        packet.* = S2CLoginDisconnectPacket{
            .base = base,
        };
        return packet;
    }

    pub fn encode(self: *S2CLoginDisconnectPacket, alloc: *Allocator, writer: anytype) !void {
        self.base.id = 0x00;

        var array_list = std.ArrayList(u8).init(alloc);
        defer array_list.deinit();
        const wr = array_list.writer();

        try utils.writeJSONStruct(alloc, wr, self.reason);

        self.base.data = array_list.toOwnedSlice();
        self.base.length = @intCast(i32, self.base.data.len) + 1;

        try self.base.encode(alloc, writer);
    }

    pub fn deinit(self: *S2CLoginDisconnectPacket, alloc: *Allocator) void {
        self.base.deinit(alloc);
        alloc.destroy(self);
    }
};