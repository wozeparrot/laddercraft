const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;
const atomic = std.atomic;
const rand = std.rand;

const zlm = @import("zlm").specializeOn(f64);

const pike = @import("pike");
const Socket = pike.Socket;
const Notifier = pike.Notifier;
const zap = @import("zap");
const sync = @import("../sync.zig");

const ladder_core = @import("ladder_core");
const network = ladder_core.network;
const packet = network.packet;
const UUID = ladder_core.UUID;
const nbt = ladder_core.nbt;
const utils = ladder_core.utils;
const world = ladder_core.world;

const Player = @import("player.zig").Player;
const Server = @import("../server.zig").Server;

pub const NetworkHandler = struct {
    alloc: *Allocator,
    network_id: i32,

    socket: Socket,
    reader: std.io.Reader(*Socket, anyerror, Socket.read),
    writer: std.io.Writer(*Socket, anyerror, Socket.write),

    keep_alive_id: std.atomic.Int(u64),
    is_alive: std.atomic.Bool,
    player: ?*Player = null,

    read_packets: sync.Queue(*packet.Packet, 128),
    write_packets: sync.Queue(*packet.Packet, 128),

    pub fn init(alloc: *Allocator, socket: Socket, network_id: i32) !*NetworkHandler {
        const network_handler = try alloc.create(NetworkHandler);
        network_handler.* = .{
            .alloc = alloc,
            .network_id = network_id,

            .socket = socket,
            .reader = undefined,
            .writer = undefined,

            .keep_alive_id = std.atomic.Int(u64).init(0),
            .is_alive = std.atomic.Bool.init(true),

            .read_packets = sync.Queue(*packet.Packet, 128){},
            .write_packets = sync.Queue(*packet.Packet, 128){},
        };
        return network_handler;
    }

    pub fn deinit(self: *NetworkHandler) void {
        self.is_alive.store(false, .SeqCst);
        self.socket.deinit();

        while (self.read_packets.tryPop() catch null) |pkt| {
            pkt.deinit(self.alloc);
        }
        while (self.write_packets.tryPop() catch null) |pkt| {
            pkt.deinit(self.alloc);
        }
        self.read_packets.close();
        self.write_packets.close();

        self.alloc.destroy(self);
    }

    pub fn sendPacket(self: *NetworkHandler, pkt: *packet.Packet) !void {
        try self.write_packets.push(pkt);
    }

    pub fn start(self: *NetworkHandler, server: *Server) !void {
        // register socket to notifier
        try self.socket.registerTo(server.notifier);

        self.reader = self.socket.reader();
        self.writer = self.socket.writer();

        try zap.runtime.spawn(.{}, NetworkHandler.read, .{ self, server });
        try zap.runtime.spawn(.{}, NetworkHandler.write, .{self});
        try zap.runtime.spawn(.{}, NetworkHandler.handle, .{ self, server });
    }

    pub fn read(self: *NetworkHandler, server: *Server) void {
        self._read(server) catch |err| {
            log.err("network_handler - read(): {}", .{@errorName(err)});
        };
    }

    pub fn _read(self: *NetworkHandler, server: *Server) !void {
        // zap.runtime.yield();

        while (self.is_alive.load(.Monotonic)) {
            // zap.runtime.yield();

            const base_pkt = packet.Packet.decode(self.alloc, self.reader) catch |err| switch (err) {
                error.SocketNotListening,
                error.OperationCancelled,
                error.EndOfStream,
                => break,
                else => return err,
            };

            self.read_packets.push(base_pkt) catch |err| break;
        }

        // connection is dead
        if(server.is_alive.load(.Monotonic)) self.is_alive.store(false, .SeqCst);
        if(server.is_alive.load(.Monotonic) and self.player == null) self.deinit();
    }

    pub fn write(self: *NetworkHandler) void {
        self._write() catch |err| {
            log.err("network_handler - write(): {}", .{@errorName(err)});
        };
    }

    pub fn _write(self: *NetworkHandler) !void {
        // zap.runtime.yield();

        while (self.is_alive.load(.Monotonic)) {
            // zap.runtime.yield();

            while (try self.write_packets.tryPop()) |base_pkt| {
                try base_pkt.encode(self.alloc, self.writer);
                base_pkt.deinit(self.alloc);
            }
        }
    }

    pub fn handle(self: *NetworkHandler, server: *Server) void {
        self._handle(server) catch |err| {
            log.err("network_handler - handle(): {}", .{@errorName(err)});
        };
    }

    pub fn _handle(self: *NetworkHandler, server: *Server) !void {
        // zap.runtime.yield();

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
            // add player to group and start player
            try server.findBestGroup(self.player.?);

            // send join game packets
            try self.transistionToPlay(server);

            // start player
            try self.player.?.start(server.notifier);

            // main packet handling loop
            while (self.is_alive.load(.Monotonic)) {
                // zap.runtime.yield();

                while (try self.read_packets.tryPop()) |base_pkt| {
                    // handle a play packet
                    switch (base_pkt.id) {
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
                        // player block placement
                        0x2e => {
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
                            _ = try self.player.?.group.?.setBlock(pos, 0x11);
                            pkt.deinit(self.alloc);
                            base_pkt.deinit(self.alloc);
                        },
                        else => {
                            log.err("Unknown play packet: {}", .{base_pkt});
                            base_pkt.deinit(self.alloc);
                        },
                    }
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
            while (try self.read_packets.tryPop()) |base_pkt| {
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
                            spkt.uuid = UUID.new(&std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp())).random);
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
        }
        return HandshakeReturnData{ .completed = false, .uuid = undefined, .username = undefined };
    }

    fn transistionToPlay(self: *NetworkHandler, server: *Server) !void {
        // send join game packet
        const spkt = try packet.S2CJoinGamePacket.init(self.alloc);
        spkt.entity_id = self.network_id;
        spkt.gamemode = .{ .mode = .creative, .hardcore = false };
        spkt.dimension_codec = network.BASIC_DIMENSION_CODEC;
        spkt.dimension = network.BASIC_DIMENSION;
        log.debug("{}", .{spkt});
        try self.sendPacket(try spkt.encode(self.alloc));
        spkt.deinit(self.alloc);

        // send player position look packet
        const spkt3 = try packet.S2CPlayerPositionLookPacket.init(self.alloc);
        spkt3.pos = zlm.vec3(0, 63, 0);
        log.debug("{}", .{spkt3});
        try self.sendPacket(try spkt3.encode(self.alloc));
        spkt3.deinit(self.alloc);

        // send spawn position packet
        const spkt4 = try packet.S2CSpawnPositionPacket.init(self.alloc);
        spkt4.pos = zlm.vec3(0, 63, 0);
        log.debug("{}", .{spkt4});
        try self.sendPacket(try spkt4.encode(self.alloc));
        spkt4.deinit(self.alloc);

        // send hand slot packet
        const spkt5 = try packet.S2CHeldItemChangePacket.init(self.alloc);
        log.debug("{}", .{spkt5});
        try self.sendPacket(try spkt5.encode(self.alloc));
        spkt5.deinit(self.alloc);
    }
};
