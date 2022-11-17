const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;
const atomic = std.atomic;
const rand = std.rand;
const net = std.net;

const zlm = @import("zlm").SpecializeOn(f64);

const ladder_core = @import("ladder_core");
const network = ladder_core.network;
const packet = network.packet;
const UUID = ladder_core.UUID;
const nbt = ladder_core.nbt;
const utils = ladder_core.utils;
const world = ladder_core.world;
const chat = ladder_core.chat;
const registry = ladder_core.registry;

const Player = @import("player.zig").Player;
const Server = @import("../server.zig").Server;

pub const NetworkHandler = struct {
    alloc: Allocator,
    read_frame: @Frame(NetworkHandler.read),
    write_frame: @Frame(NetworkHandler.write),

    conn: net.StreamServer.Connection,
    reader: std.net.Stream.Reader,
    writer: std.net.Stream.Writer,

    keep_alive_id: std.atomic.Atomic(u64),
    is_alive: std.atomic.Atomic(bool),
    player: ?*Player = null,

    read_packets: *std.event.Channel(*packet.Packet),
    read_packets_buf: [128]*packet.Packet = undefined,
    write_packets: *std.event.Channel(*packet.Packet),
    write_packets_buf: [256]*packet.Packet = undefined,

    pub fn init(alloc: Allocator, conn: net.StreamServer.Connection) !*NetworkHandler {
        const network_handler = try alloc.create(NetworkHandler);
        network_handler.* = .{
            .alloc = alloc,
            .read_frame = undefined,
            .write_frame = undefined,

            .conn = conn,
            .reader = undefined,
            .writer = undefined,

            .keep_alive_id = std.atomic.Atomic(u64).init(0),
            .is_alive = std.atomic.Atomic(bool).init(true),

            .read_packets = try alloc.create(std.event.Channel(*packet.Packet)),
            .write_packets = try alloc.create(std.event.Channel(*packet.Packet)),
        };
        return network_handler;
    }

    pub fn deinit(self: *NetworkHandler) void {
        self.is_alive.store(false, .SeqCst);
        self.conn.stream.close();

        await self.read_frame;
        await self.write_frame;

        self.read_packets.deinit();
        self.write_packets.deinit();

        self.alloc.destroy(self);
    }

    pub fn sendPacket(self: *NetworkHandler, pkt: *packet.Packet) void {
        self.write_packets.put(pkt);
    }

    pub fn start(self: *NetworkHandler, server: *Server) !void {
        self.read_packets.init(self.read_packets_buf[0..]);
        self.write_packets.init(self.write_packets_buf[0..]);

        self.reader = self.conn.stream.reader();
        self.writer = self.conn.stream.writer();

        self.read_frame = async self.read(server);
        self.write_frame = async self.write();
        try std.event.Loop.instance.?.runDetached(self.alloc, NetworkHandler.handle, .{ self, server });
    }

    pub fn read(self: *NetworkHandler, server: *Server) void {
        self._read(server) catch |err| {
            log.err("network_handler - read(): {s}", .{@errorName(err)});
        };
    }

    pub fn _read(self: *NetworkHandler, server: *Server) !void {
        _ = server;
        while (self.is_alive.load(.Monotonic)) {
            const base_pkt = packet.Packet.decode(self.alloc, self.reader) catch |err| switch (err) {
                error.NotOpenForReading,
                error.OperationAborted,
                error.BrokenPipe,
                error.EndOfStream,
                error.ConnectionResetByPeer,
                => break,
                else => return err,
            };

            self.read_packets.put(base_pkt);
        }

        // connection is dead
        self.is_alive.store(false, .SeqCst);
    }

    pub fn write(self: *NetworkHandler) void {
        self._write() catch |err| {
            log.err("network_handler - write(): {s}", .{@errorName(err)});
            self.is_alive.store(false, .SeqCst);
        };
    }

    pub fn _write(self: *NetworkHandler) !void {
        while (self.is_alive.load(.Monotonic)) {
            const base_pkt = self.write_packets.get();
            try base_pkt.encode(self.alloc, self.writer);
            base_pkt.deinit(self.alloc);
        }
    }

    pub fn handle(self: *NetworkHandler, server: *Server) void {
        self._handle(server) catch |err| {
            log.err("network_handler - handle(): {s}", .{@errorName(err)});
        };

        if (self.player == null) self.deinit();
    }

    pub fn _handle(self: *NetworkHandler, server: *Server) !void {
        // check valid handshake and login
        const handshake_return = self.handleHandshake(server) catch |err| {
            self.is_alive.store(false, .SeqCst);
            log.info("network_handler - _handle(): handshake failed: {s}", .{@errorName(err)});
            return;
        };
        if (handshake_return.completed) {
            // create player
            self.player = try Player.init(self.alloc, self);
            // set player uuid and username
            self.player.?.player.base.uuid = handshake_return.uuid;
            self.player.?.player.username = handshake_return.username;
            self.player.?.player.base.entity_id = server.nextEntityId();

            // find the best group to put the player in
            const group = try server.findBestGroup(self.player.?);
            // transfer the player to the group
            try server.transferToGroup(self.player.?, group);

            // send join game packets
            try self.transistionToPlay(server);

            log.debug("transitioned to play state for {s}", .{self.player.?.player.username});

            // start player
            try self.player.?.start();

            // main packet handling loop
            while (self.is_alive.load(.Monotonic)) {
                const base_pkt = self.read_packets.get();
                // handle a play packet
                switch (base_pkt.id) {
                    packet.C2SChatMessagePacket.PacketID => {
                        const pkt = try packet.C2SChatMessagePacket.decode(self.alloc, base_pkt);

                        const gpkt = try packet.S2CSystemChatMessagePacket.init(self.alloc);
                        gpkt.message = chat.Text{
                            .text = try std.mem.join(self.alloc, "", &[_][]const u8{ "[", self.player.?.player.username, "] ", pkt.message }),
                        };
                        try self.player.?.group.?.server.sendPacketToAll(try gpkt.encode(self.alloc), null);
                        self.alloc.free(gpkt.message.text);
                        gpkt.deinit(self.alloc);

                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // player position
                    packet.C2SPlayerPositionPacket.PacketID => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();
                        const pkt = try packet.C2SPlayerPositionPacket.decode(self.alloc, base_pkt);
                        self.player.?.player.base.last_pos = self.player.?.player.base.pos;
                        self.player.?.player.base.pos = zlm.vec3(pkt.x, pkt.y, pkt.z);
                        self.player.?.player.base.on_ground = pkt.on_ground;
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);

                        const gpkt = try packet.S2CEntityPositionPacket.init(self.alloc);
                        gpkt.entity_id = self.player.?.player.base.entity_id;
                        gpkt.delta = zlm.vec3(
                            ((self.player.?.player.base.pos.x * 32 - self.player.?.player.base.last_pos.x * 32) * 128),
                            ((self.player.?.player.base.pos.y * 32 - self.player.?.player.base.last_pos.y * 32) * 128),
                            ((self.player.?.player.base.pos.z * 32 - self.player.?.player.base.last_pos.z * 32) * 128),
                        );
                        gpkt.on_ground = self.player.?.player.base.on_ground;
                        try self.player.?.group.?.sendPacketToAll(try gpkt.encode(self.alloc), self.player);
                        gpkt.deinit(self.alloc);
                    },
                    // player position and rotation
                    packet.C2SPlayerPositionRotationPacket.PacketID => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();
                        const pkt = try packet.C2SPlayerPositionRotationPacket.decode(self.alloc, base_pkt);
                        self.player.?.player.base.last_pos = self.player.?.player.base.pos;
                        self.player.?.player.base.pos = zlm.vec3(pkt.x, pkt.y, pkt.z);
                        self.player.?.player.base.last_look = self.player.?.player.base.look;
                        self.player.?.player.base.look = zlm.vec2(pkt.yaw, pkt.pitch);
                        self.player.?.player.base.on_ground = pkt.on_ground;
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);

                        const gpkt = try packet.S2CEntityPositionRotationPacket.init(self.alloc);
                        gpkt.entity_id = self.player.?.player.base.entity_id;
                        gpkt.delta = zlm.vec3(
                            ((self.player.?.player.base.pos.x * 32 - self.player.?.player.base.last_pos.x * 32) * 128),
                            ((self.player.?.player.base.pos.y * 32 - self.player.?.player.base.last_pos.y * 32) * 128),
                            ((self.player.?.player.base.pos.z * 32 - self.player.?.player.base.last_pos.z * 32) * 128),
                        );
                        gpkt.look = self.player.?.player.base.look;
                        gpkt.on_ground = self.player.?.player.base.on_ground;
                        try self.player.?.group.?.sendPacketToAll(try gpkt.encode(self.alloc), self.player);
                        gpkt.deinit(self.alloc);

                        const gpkt2 = try packet.S2CEntityHeadLookPacket.init(self.alloc);
                        gpkt2.entity_id = self.player.?.player.base.entity_id;
                        gpkt2.look = self.player.?.player.base.look;
                        try self.player.?.group.?.sendPacketToAll(try gpkt2.encode(self.alloc), self.player);
                        gpkt2.deinit(self.alloc);
                    },
                    // player rotation
                    packet.C2SPlayerRotationPacket.PacketID => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();
                        const pkt = try packet.C2SPlayerRotationPacket.decode(self.alloc, base_pkt);
                        self.player.?.player.base.last_look = self.player.?.player.base.look;
                        self.player.?.player.base.look = zlm.vec2(pkt.yaw, pkt.pitch);
                        self.player.?.player.base.on_ground = pkt.on_ground;
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);

                        const gpkt = try packet.S2CEntityRotationPacket.init(self.alloc);
                        gpkt.entity_id = self.player.?.player.base.entity_id;
                        gpkt.look = self.player.?.player.base.look;
                        gpkt.on_ground = self.player.?.player.base.on_ground;
                        try self.player.?.group.?.sendPacketToAll(try gpkt.encode(self.alloc), self.player);
                        gpkt.deinit(self.alloc);

                        const gpkt2 = try packet.S2CEntityHeadLookPacket.init(self.alloc);
                        gpkt2.entity_id = self.player.?.player.base.entity_id;
                        gpkt2.look = self.player.?.player.base.look;
                        try self.player.?.group.?.sendPacketToAll(try gpkt2.encode(self.alloc), self.player);
                        gpkt2.deinit(self.alloc);
                    },
                    // player action
                    packet.C2SPlayerActionPacket.PacketID => {
                        const pkt = try packet.C2SPlayerActionPacket.decode(self.alloc, base_pkt);
                        if (pkt.status == 0) {
                            var pos = pkt.position;
                            _ = try self.player.?.group.?.setBlock(pos, 0x0);
                        }
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // held item change
                    packet.C2SHeldItemChangePacket.PacketID => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();
                        const pkt = try packet.C2SHeldItemChangePacket.decode(self.alloc, base_pkt);
                        self.player.?.player.selected_hotbar_slot = pkt.slot;
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // creative inventory action
                    packet.C2SCreativeInventoryActionPacket.PacketID => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();
                        const pkt = try packet.C2SCreativeInventoryActionPacket.decode(self.alloc, base_pkt);
                        if (pkt.slot > 0 and pkt.slot <= 45) self.player.?.player.inventory.slots[@intCast(usize, pkt.slot)] = pkt.clicked_item;
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // player hand animation
                    packet.C2SSwingHandPacket.PacketID => {
                        const pkt = try packet.C2SSwingHandPacket.decode(self.alloc, base_pkt);

                        switch (pkt.hand) {
                            0 => {
                                const gpkt = try packet.S2CEntityAnimationPacket.init(self.alloc);
                                gpkt.entity_id = self.player.?.player.base.entity_id;
                                gpkt.animation = 0;
                                try self.player.?.group.?.sendPacketToAll(try gpkt.encode(self.alloc), self.player);
                                gpkt.deinit(self.alloc);
                            },
                            1 => {
                                const gpkt = try packet.S2CEntityAnimationPacket.init(self.alloc);
                                gpkt.entity_id = self.player.?.player.base.entity_id;
                                gpkt.animation = 3;
                                try self.player.?.group.?.sendPacketToAll(try gpkt.encode(self.alloc), self.player);
                                gpkt.deinit(self.alloc);
                            },
                            else => {},
                        }

                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // player use item on
                    packet.C2SPlayerUseItemOnPacket.PacketID => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();

                        const pkt = try packet.C2SPlayerUseItemOnPacket.decode(self.alloc, base_pkt);
                        var pos = pkt.position;
                        switch (pkt.face) {
                            0 => pos.y -= 1,
                            1 => pos.y += 1,
                            2 => pos.z -= 1,
                            3 => pos.z += 1,
                            4 => pos.x -= 1,
                            5 => pos.x += 1,
                            else => {},
                        }
                        if (!self.player.?.player.checkBlockCollision(pos.toVec3())) {
                            if (self.player.?.player.inventory.slots[@as(usize, self.player.?.player.selected_hotbar_slot) + 36]) |slot| {
                                _ = try self.player.?.group.?.setBlock(pos, @intCast(world.block.BlockState, registry.BLOCKS.BlockToDefaultState[registry.ITEMS.ItemToBlock[@intCast(usize, slot.id)]]));
                            } else if (self.player.?.player.inventory.slots[45]) |slot|
                                _ = try self.player.?.group.?.setBlock(pos, @intCast(world.block.BlockState, registry.BLOCKS.BlockToDefaultState[registry.ITEMS.ItemToBlock[@intCast(usize, slot.id)]]));
                        }
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    else => {
                        log.err("Unknown play packet: {s}", .{base_pkt});
                        base_pkt.deinit(self.alloc);
                    },
                }
            }
        } else self.is_alive.store(false, .SeqCst);
    }

    // handle handshake and login before creating a player (must write packets manually)
    const HandshakeReturnData = struct { completed: bool, uuid: UUID, username: []const u8 };
    fn handleHandshake(self: *NetworkHandler, server: *Server) !HandshakeReturnData {
        _ = server;
        // current connection state
        var conn_state: network.client.ConnectionState = .handshake;

        // loop until we reach play state or close the connection
        while (self.is_alive.load(.Monotonic)) {
            const base_pkt = self.read_packets.get();
            defer base_pkt.deinit(self.alloc);

            switch (base_pkt.id) {
                0x00 => switch (conn_state) {
                    .handshake => {
                        // decode handshake packet
                        const pkt = try packet.C2SHandshakePacket.decode(self.alloc, base_pkt);
                        defer pkt.deinit(self.alloc);
                        log.debug("{}", .{pkt});

                        if (pkt.next_state == .login) {
                            // make sure protocol version matches
                            if (pkt.protocol_version == 760) {
                                // login state
                                conn_state = .login;
                            } else {
                                const spkt = try packet.S2CLoginDisconnectPacket.init(self.alloc);
                                defer spkt.deinit(self.alloc);
                                spkt.reason = .{ .text = "Protocol version mismatch!" };
                                const bspkt = try spkt.encode(self.alloc);
                                defer bspkt.deinit(self.alloc);
                                log.debug("{}", .{spkt});
                                try bspkt.encode(self.alloc, self.writer);

                                return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
                            }
                        } else {
                            conn_state = .status;
                        }
                    },
                    .login => {
                        // decode login start packet
                        const pkt = try packet.C2SLoginStartPacket.decode(self.alloc, base_pkt);
                        defer pkt.deinit(self.alloc);
                        log.debug("{}", .{pkt});

                        // send login success packet
                        const spkt = try packet.S2CLoginSuccessPacket.init(self.alloc);
                        defer spkt.deinit(self.alloc);
                        spkt.uuid = UUID.newv4(&std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp())).random());
                        spkt.username = pkt.username;
                        const bspkt = try spkt.encode(self.alloc);
                        defer bspkt.deinit(self.alloc);
                        log.debug("{}", .{spkt});
                        try bspkt.encode(self.alloc, self.writer);

                        const username = try self.alloc.dupe(u8, pkt.username);
                        return HandshakeReturnData{
                            .completed = true,
                            .uuid = spkt.uuid,
                            .username = username,
                        };
                    },
                    .status => {
                        // send status response packet
                        const spkt = try packet.S2CStatusResponsePacket.init(self.alloc);
                        defer spkt.deinit(self.alloc);
                        // TODO: make this not hardcoded json
                        spkt.response = try self.alloc.dupe(u8,
                            \\{
                            \\    "version": {
                            \\        "name": "1.19.2",
                            \\        "protocol": 760
                            \\    },
                            \\    "players": {
                            \\        "max": 0,
                            \\        "online": 0
                            \\    },
                            \\    "description": {
                            \\        "text": "Welcome to laddercraft!"
                            \\    },
                            \\    "favicon": "data:image/png;base64,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",
                            \\    "previewsChat": false,
                            \\    "enforcesSecureChat": false
                            \\}
                        );
                        const bspkt = try spkt.encode(self.alloc);
                        defer bspkt.deinit(self.alloc);
                        log.debug("{}", .{spkt});
                        try bspkt.encode(self.alloc, self.writer);
                    },
                    else => {
                        return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
                    },
                },
                0x01 => {
                    // decode login start packet
                    const pkt = try packet.C2SPingRequestPacket.decode(self.alloc, base_pkt);
                    defer pkt.deinit(self.alloc);
                    log.debug("{}", .{pkt});

                    // send login success packet
                    const spkt = try packet.S2CPingResponsePacket.init(self.alloc);
                    defer spkt.deinit(self.alloc);
                    spkt.payload = pkt.payload;
                    const bspkt = try spkt.encode(self.alloc);
                    defer bspkt.deinit(self.alloc);
                    log.debug("{}", .{spkt});
                    try bspkt.encode(self.alloc, self.writer);

                    return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
                },
                else => {
                    log.err("Unknown handshake packet: {}", .{base_pkt});
                    return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
                },
            }
        }
        return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
    }

    fn transistionToPlay(self: *NetworkHandler, server: *Server) !void {
        _ = server;
        // send join game packet
        const spkt = try packet.S2CJoinGamePacket.init(self.alloc);
        spkt.entity_id = self.player.?.player.base.entity_id;
        spkt.gamemode = .{ .mode = .creative, .hardcore = false };
        spkt.registry_codec = network.BASIC_REGISTRY_CODEC;
        self.sendPacket(try spkt.encode(self.alloc));
        log.debug("sent join game packet: {}", .{spkt.base});
        spkt.deinit(self.alloc);

        // send player position look packet
        const spkt2 = try packet.S2CPlayerPositionLookPacket.init(self.alloc);
        spkt2.pos = self.player.?.player.base.pos;
        self.sendPacket(try spkt2.encode(self.alloc));
        log.debug("sent player position look packet: {}", .{spkt2.base});
        spkt2.deinit(self.alloc);

        // send spawn position packet
        const spkt3 = try packet.S2CSpawnPositionPacket.init(self.alloc);
        spkt3.pos = self.player.?.player.base.pos;
        self.sendPacket(try spkt3.encode(self.alloc));
        log.debug("sent spawn position packet: {}", .{spkt3.base});
        spkt3.deinit(self.alloc);

        // send hand slot packet
        const spkt4 = try packet.S2CHeldItemChangePacket.init(self.alloc);
        spkt4.slot = self.player.?.player.selected_hotbar_slot;
        self.sendPacket(try spkt4.encode(self.alloc));
        log.debug("sent hand slot packet: {}", .{spkt4.base});
        spkt4.deinit(self.alloc);
    }
};
