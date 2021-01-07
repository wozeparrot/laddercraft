const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;
const atomic = std.atomic;
const rand = std.rand;
const net = std.net;

const zlm = @import("zlm").specializeOn(f64);

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
    alloc: *Allocator,
    read_frame: @Frame(NetworkHandler.read),
    write_frame: @Frame(NetworkHandler.write),

    conn: net.StreamServer.Connection,
    reader: std.fs.File.Reader,
    writer: std.fs.File.Writer,

    keep_alive_id: std.atomic.Int(u64),
    is_alive: std.atomic.Bool,
    player: ?*Player = null,

    read_packets: *std.event.Channel(*packet.Packet),
    read_packets_buf: [128]*packet.Packet = undefined,
    write_packets: *std.event.Channel(*packet.Packet),
    write_packets_buf: [256]*packet.Packet = undefined,

    pub fn init(alloc: *Allocator, conn: net.StreamServer.Connection) !*NetworkHandler {
        const network_handler = try alloc.create(NetworkHandler);
        network_handler.* = .{
            .alloc = alloc,
            .read_frame = undefined,
            .write_frame = undefined,

            .conn = conn,
            .reader = undefined,
            .writer = undefined,

            .keep_alive_id = std.atomic.Int(u64).init(0),
            .is_alive = std.atomic.Bool.init(true),

            .read_packets = try alloc.create(std.event.Channel(*packet.Packet)),
            .write_packets = try alloc.create(std.event.Channel(*packet.Packet)),
        };
        return network_handler;
    }

    pub fn deinit(self: *NetworkHandler) void {
        self.is_alive.store(false, .SeqCst);
        self.conn.file.close();

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

        self.reader = self.conn.file.reader();
        self.writer = self.conn.file.writer();

        // try std.event.Loop.instance.?.runDetached(self.alloc, NetworkHandler.read, .{ self, server });
        // try std.event.Loop.instance.?.runDetached(self.alloc, NetworkHandler.write, .{self});
        self.read_frame = async self.read(server);
        self.write_frame = async self.write();
        try std.event.Loop.instance.?.runDetached(self.alloc, NetworkHandler.handle, .{ self, server });
    }

    pub fn read(self: *NetworkHandler, server: *Server) void {
        self._read(server) catch |err| {
            log.err("network_handler - read(): {}", .{@errorName(err)});
        };
    }

    pub fn _read(self: *NetworkHandler, server: *Server) !void {
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
            log.err("network_handler - write(): {}", .{@errorName(err)});
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
            log.err("network_handler - handle(): {}", .{@errorName(err)});
        };

        if (self.player == null) self.deinit();
    }

    pub fn _handle(self: *NetworkHandler, server: *Server) !void {
        // check valid handshake and login
        const handshake_return = self.handleHandshake(server) catch |err| {
            self.is_alive.store(false, .SeqCst);
            return;
        };
        if (handshake_return.completed) {
            // remove from server holding
            const held = server.holding_lock.acquire();
            server.holding.removeAssertDiscard(self);
            held.release();

            // create player
            self.player = try Player.init(self.alloc, self);
            // set player uuid and username
            self.player.?.player.base.uuid = handshake_return.uuid;
            self.player.?.player.username = handshake_return.username;
            self.player.?.player.base.entity_id = server.nextEntityId();
            // add player to group and start player
            try server.findBestGroup(self.player.?);

            // send join game packets
            try self.transistionToPlay(server);

            // start player
            try self.player.?.start();

            // main packet handling loop
            while (self.is_alive.load(.Monotonic)) {
                const base_pkt = self.read_packets.get();
                // handle a play packet
                switch (base_pkt.id) {
                    0x03 => {
                        const pkt = try packet.C2SChatMessagePacket.decode(self.alloc, base_pkt);

                        const gpkt = try packet.S2CChatMessagePacket.init(self.alloc);
                        gpkt.message = chat.Text{
                            .text = try std.mem.join(self.alloc, "", &[_][]const u8{"[", self.player.?.player.username, "] ", pkt.message}),
                        };
                        gpkt.sender = self.player.?.player.base.uuid;
                        try self.player.?.group.?.server.sendPacketToAll(try gpkt.encode(self.alloc), null);
                        self.alloc.free(gpkt.message.text);
                        gpkt.deinit(self.alloc);

                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // player position
                    0x12 => {
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
                    0x13 => {
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
                    0x14 => {
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
                    // player digging
                    0x1b => {
                        const pkt = try packet.C2SPlayerDiggingPacket.decode(self.alloc, base_pkt);
                        if (pkt.status == 0) {
                            var pos = pkt.position;
                            _ = try self.player.?.group.?.setBlock(pos, 0x0);
                        }
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // held item change
                    0x25 => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();
                        const pkt = try packet.C2SHeldItemChangePacket.decode(self.alloc, base_pkt);
                        self.player.?.player.selected_hotbar_slot = pkt.slot;
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // creative inventory action
                    0x28 => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();
                        const pkt = try packet.C2SCreativeInventoryActionPacket.decode(self.alloc, base_pkt);
                        if (pkt.slot > 0 and pkt.slot <= 45) self.player.?.player.inventory.slots[@intCast(usize, pkt.slot)] = pkt.clicked_item;
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    // player hand animation
                    0x2c => {
                        const pkt = try packet.C2SAnimationPacket.decode(self.alloc, base_pkt);
                        
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
                    // player block placement
                    0x2e => {
                        const player_held = self.player.?.player_lock.acquire();
                        defer player_held.release();

                        const pkt = try packet.C2SPlayerBlockPlacementPacket.decode(self.alloc, base_pkt);
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
                        if (pos.x != @floatToInt(i32, std.math.floor(self.player.?.player.base.pos.x)) or pos.y != @floatToInt(i32, std.math.floor(self.player.?.player.base.pos.y)) or pos.z != @floatToInt(i32, std.math.floor(self.player.?.player.base.pos.z))) {
                            if (self.player.?.player.inventory.slots[@as(usize, self.player.?.player.selected_hotbar_slot) + 36]) |slot| {
                                _ = try self.player.?.group.?.setBlock(pos, @intCast(world.block.BlockState, registry.BLOCKS.BlockToDefaultState[registry.ITEMS.ItemToBlock[@intCast(usize, slot.id)]]));
                            } else if (self.player.?.player.inventory.slots[45]) |slot|
                                _ = try self.player.?.group.?.setBlock(pos, @intCast(world.block.BlockState, registry.BLOCKS.BlockToDefaultState[registry.ITEMS.ItemToBlock[@intCast(usize, slot.id)]]));
                        }
                        pkt.deinit(self.alloc);
                        base_pkt.deinit(self.alloc);
                    },
                    else => {
                        log.err("Unknown play packet: {}", .{base_pkt});
                        base_pkt.deinit(self.alloc);
                    },
                }
            }
        } else self.is_alive.store(false, .SeqCst);
    }

    // handle handshake and login before creating a player (must write packets manually)
    const HandshakeReturnData = struct { completed: bool, uuid: UUID, username: []const u8 };
    fn handleHandshake(self: *NetworkHandler, server: *Server) !HandshakeReturnData {
        // current connection state
        var conn_state: network.client.ConnectionState = .handshake;

        // loop until we reach play state or close the connection
        while (self.is_alive.load(.SeqCst)) {
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
                            if (pkt.protocol_version == 754) {
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
                        spkt.uuid = UUID.newv4(&std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp())).random);
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
                        return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
                    },
                    else => {
                        return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
                    },
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
        // send join game packet
        const spkt = try packet.S2CJoinGamePacket.init(self.alloc);
        spkt.entity_id = self.player.?.player.base.entity_id;
        spkt.gamemode = .{ .mode = .creative, .hardcore = false };
        spkt.dimension_codec = network.BASIC_DIMENSION_CODEC;
        spkt.dimension = network.BASIC_DIMENSION;
        log.debug("{}", .{spkt});
        self.sendPacket(try spkt.encode(self.alloc));
        spkt.deinit(self.alloc);

        // send player position look packet
        const spkt2 = try packet.S2CPlayerPositionLookPacket.init(self.alloc);
        spkt2.pos = self.player.?.player.base.pos;
        log.debug("{}", .{spkt2});
        self.sendPacket(try spkt2.encode(self.alloc));
        spkt2.deinit(self.alloc);

        // send spawn position packet
        const spkt3 = try packet.S2CSpawnPositionPacket.init(self.alloc);
        spkt3.pos = self.player.?.player.base.pos;
        log.debug("{}", .{spkt3});
        self.sendPacket(try spkt3.encode(self.alloc));
        spkt3.deinit(self.alloc);

        // send hand slot packet
        const spkt4 = try packet.S2CHeldItemChangePacket.init(self.alloc);
        spkt4.slot = self.player.?.player.selected_hotbar_slot;
        log.debug("{}", .{spkt4});
        self.sendPacket(try spkt4.encode(self.alloc));
        spkt4.deinit(self.alloc);
    }
};
