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

const ladder_core = @import("ladder_core");
const network = ladder_core.network;
const packet = network.packet;
const UUID = ladder_core.UUID;
const nbt = ladder_core.nbt;
const utils = ladder_core.utils;
const world = ladder_core.world;

const Player = @import("player.zig").Player;

pub const NetworkHandler = struct {
    frame: @Frame(NetworkHandler.handle),
    arena: std.heap.ArenaAllocator,
    network_id: i32,

    socket: Socket,

    pub fn init(alloc: *Allocator, socket: Socket, network_id: i32) !*NetworkHandler {
        const network_handler = try alloc.create(NetworkHandler);
        network_handler.* = .{
            .frame = undefined,
            .arena = std.heap.ArenaAllocator.init(alloc),
            .network_id = network_id,

            .socket = socket,
        };
        return network_handler;
    }

    pub fn deinit(self: *NetworkHandler) void {
        self.socket.deinit();
        self.arena.deinit();

        await self.frame catch |err| {
            log.err("{} while awaiting network_handler frame!", .{@errorName(err)});
        };
    }

    pub fn start(self: *NetworkHandler, player: *Player) void {
        self.frame = async self.handle(player);
    }

    pub fn handle(self: *NetworkHandler, player: *Player) !void {
        // reader and writer
        const reader = self.socket.reader();
        const writer = self.socket.writer();

        try self.transistionToPlay(player, reader, writer);

        // main loop
        while (player.is_alive.load(.SeqCst)) {
            // decode a basic packet
            const base_pkt = try packet.Packet.decode(&self.arena.allocator, reader);

            // handle a packet
            switch (base_pkt.id) {
                else => {
                    log.err("Unknown play packet: {}", .{base_pkt});
                    base_pkt.deinit(&self.arena.allocator);
                },
            }

            // reset watchdog
            player.watchdog.reset();
        }
    }

    fn transistionToPlay(self: *NetworkHandler, player: *Player, reader: anytype, writer: anytype) !void {
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
        try spkt.encode(&self.arena.allocator, writer);
        log.debug("{}\n", .{spkt});
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
                try spkt2.encode(&self.arena.allocator, writer);
                log.debug("{}\n", .{spkt2});
                spkt2.deinit(&self.arena.allocator);
            }
        }

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
    }
};
