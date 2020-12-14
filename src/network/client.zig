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

const mc_core = @import("minecart_core");
const network = mc_core.network;
const packet = network.packet;
const UUID = mc_core.UUID;
const nbt = mc_core.nbt;
const utils = mc_core.utils;
const world = mc_core.world;

const Server = @import("server.zig").Server;
const ClientQueue = @import("server.zig").ClientQueue;

pub const Client = struct {
    id: i32,
    frame: @Frame(Client.handle),
    arena: std.heap.ArenaAllocator,

    socket: Socket,
    conn_state: network.client.ConnectionState,

    should_close: atomic.Bool = atomic.Bool.init(false),

    pub fn handle(self: *Client, server: *Server, notifier: *const Notifier) !void {
        // register client on server
        var node = ClientQueue.Node{ .data = self };
        server.clients.put(&node);
        // try to remove client
        defer if (server.clients.remove(&node)) {
            suspend {
                self.socket.deinit();
                self.arena.deinit();
                server.alloc.destroy(self);
            }
        };

        // initialize client variables
        self.conn_state = .handshake;

        // register pike notifier
        try self.socket.registerTo(notifier);

        // reader and writer
        const reader = self.socket.reader();
        const writer = self.socket.writer();

        // main loop
        while (!self.should_close.load(.SeqCst)) {
            // decode a basic packet
            const base_pkt = try packet.Packet.decode(&self.arena.allocator, reader);

            // switch on current connection state
            switch (self.conn_state) {
                .handshake, .login => try self.handleHandshake(server, base_pkt, reader, writer),
                .play => try self.handlePlay(server, base_pkt, reader, writer),
                else => {},
            }

            // free the packet
            base_pkt.deinit(&self.arena.allocator);
        }
    }

    // handshake and login start
    fn handleHandshake(self: *Client, server: *Server, base_pkt: *packet.Packet, reader: anytype, writer: anytype) !void {
        switch (base_pkt.id) {
            0x00 => switch (self.conn_state) {
                .handshake => {
                    // decode handshake packet
                    const pkt = try packet.C2SHandshakePacket.decodeBase(&self.arena.allocator, base_pkt);
                    log.debug("{}\n", .{pkt});

                    // make sure protocol version matches
                    if (pkt.protocol_version == 754) {
                        // login state
                        self.conn_state = pkt.next_state;
                    } else {
                        self.should_close.store(true, .SeqCst);
                    }
                },
                .login => {
                    // decode login start packet
                    const pkt = try packet.C2SLoginStartPacket.decodeBase(&self.arena.allocator, base_pkt);
                    log.debug("{}\n", .{pkt});

                    // send login success packet
                    const spkt = try packet.S2CLoginSuccessPacket.init(&self.arena.allocator);
                    spkt.uuid = UUID.new(&std.rand.DefaultPrng.init(server.seed + @bitCast(u64, std.time.timestamp())).random);
                    spkt.username = pkt.username;
                    try spkt.encode(&self.arena.allocator, writer);
                    log.debug("{}\n", .{spkt});
                    spkt.deinit(&self.arena.allocator);

                    // play state
                    try self.transistionToPlay(server, reader, writer);
                },
                .status => {},
                else => {},
            },
            else => log.err("Unknown handshake packet: {}", .{base_pkt}),
        }
    }

    fn transistionToPlay(self: *Client, server: *Server, reader: anytype, writer: anytype) !void {
        // send join game packet
        const spkt = try packet.S2CJoinGamePacket.init(&self.arena.allocator);
        spkt.entity_id = self.id;
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
        try spkt.encode(&self.arena.allocator, writer);
        log.debug("{}\n", .{spkt});
        spkt.deinit(&self.arena.allocator);

        // send player position look packet
        const spkt3 = try packet.S2CPlayerPositionLookPacket.init(&self.arena.allocator);
        spkt3.pos = zlm.vec3(0, 63, 0);
        try spkt3.encode(&self.arena.allocator, writer);
        log.debug("{}\n", .{spkt3});
        spkt3.deinit(&self.arena.allocator);

        // send spawn position packet
        const spkt4 = try packet.S2CSpawnPositionPacket.init(&self.arena.allocator);
        spkt4.pos = zlm.vec3(0, 63, 0);
        try spkt4.encode(&self.arena.allocator, writer);
        log.debug("{}\n", .{spkt4});
        spkt4.deinit(&self.arena.allocator);

        // send hand slot packet
        // const spkt5 = try packet.S2CHeldItemChangePacket.init(&self.arena.allocator);
        // try spkt5.encode(&self.arena.allocator, writer);
        // log.debug("{}\n", .{spkt5});
        // spkt5.deinit(&self.arena.allocator);

        // send chunk
        var chunk = try world.chunk.Chunk.initFlat(&self.arena.allocator, 0, 0);
        defer chunk.deinit();
        const spkt2 = try packet.S2CChunkDataPacket.init(&self.arena.allocator);
        spkt2.chunk = chunk;
        spkt2.full_chunk = true;
        try spkt2.encode(&self.arena.allocator, writer);
        log.debug("{}\n", .{spkt2});
        spkt2.deinit(&self.arena.allocator);

        self.conn_state = .play;
    }

    fn handlePlay(self: *Client, server: *Server, base_pkt: *packet.Packet, reader: anytype, writer: anytype) !void {
        switch (base_pkt.id) {
            else => log.err("Unknown play packet: {}", .{base_pkt}),
        }
    }
};
