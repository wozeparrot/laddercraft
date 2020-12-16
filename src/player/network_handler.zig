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
    arena: std.heap.ArenaAllocator,
    network_id: i32,

    socket: Socket,
    reader: std.io.Reader(*Socket, anyerror, Socket.read),
    writer: std.io.Writer(*Socket, anyerror, Socket.write),

    keep_alive_id: std.atomic.Int(u64),
    is_alive: std.atomic.Bool,
    player: ?*Player = null,

    read_packets: std.atomic.Queue(*packet.Packet),
    write_packets: std.atomic.Queue(*packet.Packet),

    pub fn init(alloc: *Allocator, socket: Socket, network_id: i32) !*NetworkHandler {
        const network_handler = try alloc.create(NetworkHandler);
        network_handler.* = .{
            .alloc = alloc,
            .arena = std.heap.ArenaAllocator.init(alloc),
            .network_id = network_id,

            .socket = socket,
            .reader = undefined,
            .writer = undefined,

            .keep_alive_id = std.atomic.Int(u64).init(0),
            .is_alive = std.atomic.Bool.init(true),

            .read_packets = std.atomic.Queue(*packet.Packet).init(),
            .write_packets = std.atomic.Queue(*packet.Packet).init(),
        };
        return network_handler;
    }

    pub fn deinit(self: *NetworkHandler) void {
        self.is_alive.store(false, .SeqCst);

        self.socket.deinit();
        self.arena.deinit();

        self.alloc.destroy(self);
    }

    pub fn sendPacket(self: *NetworkHandler, pkt: *packet.Packet) !void {
        const node = try self.arena.allocator.create(std.atomic.Queue(*packet.Packet).Node);
        node.* = .{ .data = pkt };
        self.write_packets.put(node);
    }

    pub fn start(self: *NetworkHandler, server: *Server) !void {
        self.is_alive.store(true, .SeqCst);

        // register socket to notifier
        try self.socket.registerTo(server.notifier);

        self.reader = self.socket.reader();
        self.writer = self.socket.writer();

        try zap.runtime.spawn(.{}, NetworkHandler.read, .{ self, server });
        try zap.runtime.spawn(.{}, NetworkHandler.handle, .{ self, server });
    }

    pub fn read(self: *NetworkHandler, server: *Server) void {
        self._read(server) catch |err| {
            log.err("network_handler - read(): {}", .{@errorName(err)});
        };
    }

    pub fn _read(self: *NetworkHandler, server: *Server) !void {
        while (self.is_alive.load(.SeqCst)) {
            const base_pkt = packet.Packet.decode(&self.arena.allocator, self.reader) catch |err| switch (err) {
                error.SocketNotListening,
                error.OperationCancelled,
                error.EndOfStream,
                => break,
                else => return err,
            };

            const node = try self.arena.allocator.create(std.atomic.Queue(*packet.Packet).Node);
            node.* = .{ .data = base_pkt };
            self.read_packets.put(node);
        }

        // connection is dead
        self.is_alive.store(false, .SeqCst);
        if (self.player == null) self.deinit();
    }

    pub fn handle(self: *NetworkHandler, server: *Server) void {
        self._handle(server) catch |err| {
            log.err("network_handler - handle(): {}", .{@errorName(err)});
        };
    }

    pub fn _handle(self: *NetworkHandler, server: *Server) !void {
        // check valid handshake and login
        if (self.handleHandshake(server) catch |err| {
            self.is_alive.store(false, .SeqCst);
            return;
        }) {
            // create player
            self.player = try Player.init(self.alloc, self);
            try server.findBestGroup(self.player.?);
            try self.player.?.start(server.notifier);

            // send join game packets
            try self.transistionToPlay(server);

            // main loop
            while (self.is_alive.load(.SeqCst)) {
                while (self.read_packets.get()) |node| {
                    const base_pkt = node.data;

                    // handle a play packet
                    switch (base_pkt.id) {
                        else => {
                            log.err("Unknown play packet: {}", .{base_pkt});
                            base_pkt.deinit(&self.arena.allocator);
                            self.arena.allocator.destroy(node);
                        },
                    }
                }

                while (self.write_packets.get()) |node| {
                    const base_pkt = node.data;

                    try base_pkt.encode(&self.arena.allocator, self.writer);
                    base_pkt.deinit(&self.arena.allocator);
                    self.arena.allocator.destroy(node);
                }
            }
        } else self.is_alive.store(false, .SeqCst);
    }

    // handle handshake and login before creating a player (must write packets manually)
    fn handleHandshake(self: *NetworkHandler, server: *Server) !bool {
        // current connection state
        var conn_state: network.client.ConnectionState = .handshake;

        // loop until we reach play state or close the connection
        while (self.is_alive.load(.SeqCst)) {
            while (self.read_packets.get()) |node| {
                const base_pkt = node.data;
                defer self.arena.allocator.destroy(node);
                defer base_pkt.deinit(&self.arena.allocator);

                switch (base_pkt.id) {
                    0x00 => switch (conn_state) {
                        .handshake => {
                            // decode handshake packet
                            const pkt = try packet.C2SHandshakePacket.decode(&self.arena.allocator, base_pkt);
                            defer pkt.deinit(&self.arena.allocator);
                            log.debug("{}", .{pkt});

                            if (pkt.next_state == .login) {
                                // make sure protocol version matches
                                if (pkt.protocol_version == 754) {
                                    // login state
                                    conn_state = .login;
                                } else {
                                    const spkt = try packet.S2CLoginDisconnectPacket.init(&self.arena.allocator);
                                    defer spkt.deinit(&self.arena.allocator);
                                    spkt.reason = .{ .text = "Protocol version mismatch!" };
                                    const bspkt = try spkt.encode(&self.arena.allocator);
                                    defer bspkt.deinit(&self.arena.allocator);
                                    try bspkt.encode(&self.arena.allocator, self.writer);
                                    log.debug("{}", .{spkt});

                                    return false;
                                }
                            } else {
                                conn_state = .status;
                            }
                        },
                        .login => {
                            // decode login start packet
                            const pkt = try packet.C2SLoginStartPacket.decode(&self.arena.allocator, base_pkt);
                            defer pkt.deinit(&self.arena.allocator);
                            log.debug("{}", .{pkt});

                            // send login success packet
                            const spkt = try packet.S2CLoginSuccessPacket.init(&self.arena.allocator);
                            defer spkt.deinit(&self.arena.allocator);
                            spkt.uuid = UUID.new(&std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp())).random);
                            spkt.username = pkt.username;
                            const bspkt = try spkt.encode(&self.arena.allocator);
                            defer bspkt.deinit(&self.arena.allocator);
                            try bspkt.encode(&self.arena.allocator, self.writer);
                            log.debug("{}", .{spkt});

                            return true;
                        },
                        .status => {
                            return false;
                        },
                        else => {
                            return false;
                        },
                    },
                    else => {
                        log.err("Unknown handshake packet: {}", .{base_pkt});
                        return false;
                    },
                }
            }
        }
        return false;
    }

    fn transistionToPlay(self: *NetworkHandler, server: *Server) !void {
        // send join game packet
        const spkt = try packet.S2CJoinGamePacket.init(&self.arena.allocator);
        spkt.entity_id = self.network_id;
        spkt.gamemode = .{ .mode = .creative, .hardcore = false };
        spkt.dimension_codec = nbt.Tag{
            .compound = .{
                .name = "",
                .payload = &[_]nbt.Tag{
                    .{
                        .compound = .{
                            .name = "minecraft:dimension_type",
                            .payload = &[_]nbt.Tag{
                                .{
                                    .string = .{
                                        .name = "type",
                                        .payload = "minecraft:dimension_type",
                                    },
                                },
                                .{
                                    .list = .{
                                        .name = "value",
                                        .payload = &[_]nbt.Tag{
                                            .{
                                                .compound = .{
                                                    .name = "",
                                                    .payload = &[_]nbt.Tag{
                                                        .{
                                                            .string = .{
                                                                .name = "name",
                                                                .payload = "minecraft:overworld",
                                                            },
                                                        },
                                                        .{
                                                            .byte = .{
                                                                .name = "id",
                                                                .payload = 0,
                                                            },
                                                        },
                                                        .{
                                                            .compound = .{
                                                                .name = "element",
                                                                .payload = &[_]nbt.Tag{
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "piglin_safe",
                                                                            .payload = 0,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "natural",
                                                                            .payload = 1,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .float = .{
                                                                            .name = "ambient_light",
                                                                            .payload = 0,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .string = .{
                                                                            .name = "infiniburn",
                                                                            .payload = "minecraft:infiniburn_overworld",
                                                                        },
                                                                    },
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "respawn_anchor_works",
                                                                            .payload = 0,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "has_skylight",
                                                                            .payload = 1,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "bed_works",
                                                                            .payload = 1,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .string = .{
                                                                            .name = "effects",
                                                                            .payload = "minecraft:overworld",
                                                                        },
                                                                    },
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "has_raids",
                                                                            .payload = 1,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .int = .{
                                                                            .name = "logical_height",
                                                                            .payload = 256,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .float = .{
                                                                            .name = "coordinate_scale",
                                                                            .payload = 1.0,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "ultrawarm",
                                                                            .payload = 0,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .byte = .{
                                                                            .name = "has_ceiling",
                                                                            .payload = 0,
                                                                        },
                                                                    },
                                                                },
                                                            },
                                                        },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                    .{
                        .compound = .{
                            .name = "minecraft:worldgen/biome",
                            .payload = &[_]nbt.Tag{
                                .{
                                    .string = .{
                                        .name = "type",
                                        .payload = "minecraft:worldgen/biome",
                                    },
                                },
                                .{
                                    .list = .{
                                        .name = "value",
                                        .payload = &[_]nbt.Tag{
                                            .{
                                                .compound = .{
                                                    .name = "",
                                                    .payload = &[_]nbt.Tag{
                                                        .{
                                                            .string = .{
                                                                .name = "name",
                                                                .payload = "minecraft:plains",
                                                            },
                                                        },
                                                        .{
                                                            .int = .{
                                                                .name = "id",
                                                                .payload = 0,
                                                            },
                                                        },
                                                        .{
                                                            .compound = .{
                                                                .name = "element",
                                                                .payload = &[_]nbt.Tag{
                                                                    .{
                                                                        .string = .{
                                                                            .name = "precipitation",
                                                                            .payload = "rain",
                                                                        },
                                                                    },
                                                                    .{
                                                                        .compound = .{
                                                                            .name = "effects",
                                                                            .payload = &[_]nbt.Tag{
                                                                                .{
                                                                                    .int = .{
                                                                                        .name = "sky_color",
                                                                                        .payload = 7907327,
                                                                                    },
                                                                                },
                                                                                .{
                                                                                    .int = .{
                                                                                        .name = "water_fog_color",
                                                                                        .payload = 329011,
                                                                                    },
                                                                                },
                                                                                .{
                                                                                    .int = .{
                                                                                        .name = "fog_color",
                                                                                        .payload = 12638463,
                                                                                    },
                                                                                },
                                                                                .{
                                                                                    .int = .{
                                                                                        .name = "water_color",
                                                                                        .payload = 4159204,
                                                                                    },
                                                                                },
                                                                                .{
                                                                                    .compound = .{
                                                                                        .name = "mood_sound",
                                                                                        .payload = &[_]nbt.Tag{
                                                                                            .{
                                                                                                .int = .{
                                                                                                    .name = "tick_delay",
                                                                                                    .payload = 6000,
                                                                                                },
                                                                                            },
                                                                                            .{
                                                                                                .double = .{
                                                                                                    .name = "offset",
                                                                                                    .payload = 2.0,
                                                                                                },
                                                                                            },
                                                                                            .{
                                                                                                .string = .{
                                                                                                    .name = "sound",
                                                                                                    .payload = "minecraft:ambient.cave",
                                                                                                },
                                                                                            },
                                                                                            .{
                                                                                                .int = .{
                                                                                                    .name = "block_search_extent",
                                                                                                    .payload = 8,
                                                                                                },
                                                                                            },
                                                                                        },
                                                                                    },
                                                                                },
                                                                            },
                                                                        },
                                                                    },
                                                                    .{
                                                                        .float = .{
                                                                            .name = "depth",
                                                                            .payload = 0.125,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .float = .{
                                                                            .name = "temperature",
                                                                            .payload = 0.8,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .float = .{
                                                                            .name = "scale",
                                                                            .payload = 0.05,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .float = .{
                                                                            .name = "downfall",
                                                                            .payload = 0.4,
                                                                        },
                                                                    },
                                                                    .{
                                                                        .string = .{
                                                                            .name = "category",
                                                                            .payload = "plains",
                                                                        },
                                                                    },
                                                                },
                                                            },
                                                        },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        };
        spkt.dimension = nbt.Tag{
            .compound = .{
                .name = "",
                .payload = &[_]nbt.Tag{
                    .{
                        .byte = .{
                            .name = "piglin_safe",
                            .payload = 0,
                        },
                    },
                    .{
                        .byte = .{
                            .name = "natural",
                            .payload = 1,
                        },
                    },
                    .{
                        .float = .{
                            .name = "ambient_light",
                            .payload = 0,
                        },
                    },
                    .{
                        .string = .{
                            .name = "infiniburn",
                            .payload = "minecraft:infiniburn_overworld",
                        },
                    },
                    .{
                        .byte = .{
                            .name = "respawn_anchor_works",
                            .payload = 0,
                        },
                    },
                    .{
                        .byte = .{
                            .name = "has_skylight",
                            .payload = 1,
                        },
                    },
                    .{
                        .byte = .{
                            .name = "bed_works",
                            .payload = 1,
                        },
                    },
                    .{
                        .string = .{
                            .name = "effects",
                            .payload = "minecraft:overworld",
                        },
                    },
                    .{
                        .byte = .{
                            .name = "has_raids",
                            .payload = 1,
                        },
                    },
                    .{
                        .int = .{
                            .name = "logical_height",
                            .payload = 256,
                        },
                    },
                    .{
                        .float = .{
                            .name = "coordinate_scale",
                            .payload = 1.0,
                        },
                    },
                    .{
                        .byte = .{
                            .name = "ultrawarm",
                            .payload = 0,
                        },
                    },
                    .{
                        .byte = .{
                            .name = "has_ceiling",
                            .payload = 0,
                        },
                    },
                },
            },
        };
        try self.sendPacket(try spkt.encode(&self.arena.allocator));
        log.debug("{}", .{spkt});
        spkt.deinit(&self.arena.allocator);

        // send chunks
        var chunk = try world.chunk.Chunk.initFlat(&self.arena.allocator, 0, 0);
        defer chunk.deinit();
        var cx: i32 = -1;
        while (cx <= 1) : (cx += 1) {
            var cz: i32 = -1;
            while (cz <= 1) : (cz += 1) {
                chunk.x = cx;
                chunk.z = cz;
                const spkt2 = try packet.S2CChunkDataPacket.init(&self.arena.allocator);
                spkt2.chunk = chunk;
                spkt2.full_chunk = true;
                try self.sendPacket(try spkt2.encode(&self.arena.allocator));
                log.debug("{}", .{spkt2});
                spkt2.deinit(&self.arena.allocator);
            }
        }

        // send player position look packet
        const spkt3 = try packet.S2CPlayerPositionLookPacket.init(&self.arena.allocator);
        spkt3.pos = zlm.vec3(0, 63, 0);
        try self.sendPacket(try spkt3.encode(&self.arena.allocator));
        log.debug("{}", .{spkt3});
        spkt3.deinit(&self.arena.allocator);

        // send spawn position packet
        const spkt4 = try packet.S2CSpawnPositionPacket.init(&self.arena.allocator);
        spkt4.pos = zlm.vec3(0, 63, 0);
        try self.sendPacket(try spkt4.encode(&self.arena.allocator));
        log.debug("{}", .{spkt4});
        spkt4.deinit(&self.arena.allocator);

        // send hand slot packet
        const spkt5 = try packet.S2CHeldItemChangePacket.init(&self.arena.allocator);
        try self.sendPacket(try spkt5.encode(&self.arena.allocator));
        log.debug("{}", .{spkt5});
        spkt5.deinit(&self.arena.allocator);
    }
};
