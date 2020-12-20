const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;

const ladder_core = @import("ladder_core");
const network = ladder_core.network;
const packet = network.packet;
const lc_block = ladder_core.world.block;
const Chunk = ladder_core.world.chunk.Chunk;

const Server = @import("server.zig").Server;
const Player = @import("player/player.zig").Player;
const l_config = @import("config.zig").config;

pub const Group = struct {
    alloc: *Allocator,

    server: *Server,

    players: std.AutoArrayHashMap(*Player, void),
    players_lock: std.event.Lock,
    player_count: std.atomic.Int(u32),

    chunks: std.AutoArrayHashMap(u64, *Chunk),
    chunks_lock: std.event.Lock,

    is_alive: std.atomic.Bool,

    pub fn init(alloc: *Allocator, server: *Server) !*Group {
        const group = try alloc.create(Group);
        group.* = .{
            .alloc = alloc,

            .server = server,

            .players = std.AutoArrayHashMap(*Player, void).init(alloc),
            .players_lock = std.event.Lock{},
            .player_count = std.atomic.Int(u32).init(0),

            .chunks = std.AutoArrayHashMap(u64, *Chunk).init(alloc),
            .chunks_lock = std.event.Lock{},

            .is_alive = std.atomic.Bool.init(true),
        };
        return group;
    }

    pub fn deinit(self: *Group) void {
        self.is_alive.store(false, .SeqCst);

        const players_held = self.players_lock.acquire();
        for (self.players.items()) |entry| {
            entry.key.deinit();
        }
        players_held.release();
        self.players.deinit();

        const chunks_held = self.chunks_lock.acquire();
        for (self.chunks.items()) |entry| {
            entry.value.deinit();
        }
        chunks_held.release();
        self.chunks.deinit();

        self.alloc.destroy(self);
    }

    pub fn start(self: *Group) !void {
        try std.event.Loop.instance.?.runDetached(self.alloc, Group.run, .{self});
    }

    pub fn run(self: *Group) void {
        self._run() catch |err| {
            log.err("group - run(): {}", .{@errorName(err)});
        };
    }

    pub fn _run(self: *Group) !void {
        while (self.is_alive.load(.Monotonic)) {
            if (self.player_count.get() == 0) {
                self.is_alive.store(false, .SeqCst);
            }
        }

        const held = self.server.groups_lock.acquire();
        self.server.groups.removeAssertDiscard(self);
        held.release();
        self.deinit();
    }

    pub fn addPlayer(self: *Group, player: *Player) !void {
        const held = self.players_lock.acquire();
        defer held.release();

        _ = self.player_count.incr();
        try self.players.put(player, {});

        player.group = self;
    }

    pub fn removePlayer(self: *Group, player: *Player) !void {
        const held = self.players_lock.acquire();
        defer held.release();

        _ = self.player_count.decr();
        if (self.players.remove(player)) |entry| {
            // const pkt = try packet.S2CPlayerInfoPacket.init(self.alloc);
            // pkt.action = .remove_player;
            // pkt.players = &[_]packet.S2CPlayerInfoPlayer{
            //     .{
            //         .uuid = entry.key.player.base.uuid,

            //         .data = .{ .remove_player = {} },
            //     }
            // };
            // log.debug("{}", .{pkt});
            // try self.server.sendPacketToAll(try pkt.encode(self.alloc), null);
            // pkt.deinit(self.alloc);
        }
    }

    pub fn sendPacketToAll(self: *Group, pkt: *packet.Packet, player: ?*Player) !void {
        const held = self.players_lock.acquire();
        defer held.release();
        for (self.players.items()) |entry| {
            if (player) |p| if (entry.key == p) continue;
            entry.key.network_handler.sendPacket(try pkt.copy(self.alloc));
        }
        pkt.deinit(self.alloc);
    }

    pub fn sendPlayersToPlayer(self: *Group, player: *Player) !void {
        const held = self.players_lock.acquire();
        defer held.release();
        for (self.players.items()) |entry| {
            const player_held = entry.key.player_lock.acquire();
            defer player_held.release();

            const pkt = try packet.S2CPlayerInfoPacket.init(self.alloc);
            pkt.action = .add_player;
            pkt.players = &[_]packet.S2CPlayerInfoPlayer{.{
                .uuid = entry.key.player.base.uuid,

                .data = .{
                    .add_player = .{
                        .name = entry.key.player.username,
                        .properties = &[0]packet.S2CPlayerInfoProperties{},
                        .gamemode = 0,
                        .ping = 0,
                        .display_name = null,
                    },
                },
            }};
            log.debug("{}", .{pkt});
            player.network_handler.sendPacket(try pkt.encode(self.alloc));
            pkt.deinit(self.alloc);

            if (entry.key == player) continue;
            if (self.players.contains(player)) {
                const pkt2 = try packet.S2CSpawnPlayerPacket.init(self.alloc);
                pkt2.entity_id = entry.key.player.base.entity_id;
                pkt2.uuid = entry.key.player.base.uuid;
                pkt2.pos = entry.key.player.base.pos;
                pkt2.look = entry.key.player.base.look;
                log.debug("{}", .{pkt2});
                player.network_handler.sendPacket(try pkt2.encode(self.alloc));
                pkt2.deinit(self.alloc);
            }
        }
    }

    pub fn updatePlayerChunks(self: *Group, player: *Player) !void {
        std.event.Loop.startCpuBoundOperation();

        var needed_chunks = std.ArrayList(u64).init(self.alloc);
        defer needed_chunks.deinit();
        var loaded_chunks = std.ArrayList(u64).init(self.alloc);
        defer loaded_chunks.deinit();

        const inner_player_held = player.player_lock.acquire();
        const chunk_x = player.player.chunkX();
        const chunk_z = player.player.chunkZ();
        const last_chunk_x = player.player.last_chunk_x;
        const last_chunk_z = player.player.last_chunk_z;

        if (!(chunk_x == last_chunk_x and chunk_z == last_chunk_z)) {
            player.player.last_chunk_x = chunk_x;
            player.player.last_chunk_z = chunk_z;

            const pkt = try packet.S2CUpdateViewPositionPacket.init(self.alloc);
            pkt.chunk_x = chunk_x;
            pkt.chunk_z = chunk_z;
            player.network_handler.sendPacket(try pkt.encode(self.alloc));
            pkt.deinit(self.alloc);
        }
        inner_player_held.release();

        var x: i32 = chunk_x - @as(i32, l_config.view_distance);
        while (x <= chunk_x + @as(i32, l_config.view_distance)) : (x += 1) {
            var z: i32 = chunk_z - @as(i32, l_config.view_distance);
            while (z <= chunk_z + @as(i32, l_config.view_distance)) : (z += 1) {
                const held = player.loaded_chunks_lock.acquire();
                defer held.release();
                const chunk_id = (@bitCast(u64, @as(i64, x)) << 32) | @bitCast(u32, z);
                if (!player.loaded_chunks.contains(chunk_id)) {
                    try needed_chunks.append(chunk_id);
                } else {
                    try loaded_chunks.append(chunk_id);
                    player.loaded_chunks.removeAssertDiscard(chunk_id);
                }
            }
        }

        const chunks_held = player.loaded_chunks_lock.acquire();
        for (player.loaded_chunks.items()) |entry| {
            const pkt = try packet.S2CUnloadChunkPacket.init(self.alloc);
            pkt.chunk_x = @bitCast(i32, @truncate(u32, entry.key >> 32));
            pkt.chunk_z = @bitCast(i32, @truncate(u32, entry.key));
            player.network_handler.sendPacket(try pkt.encode(self.alloc));
            pkt.deinit(self.alloc);
            player.loaded_chunks.removeAssertDiscard(entry.key);
        }
        chunks_held.release();

        for (needed_chunks.items) |chunk_id| {
            if (self.containsChunk(chunk_id)) {
                const player_held = player.loaded_chunks_lock.acquire();
                defer player_held.release();
                try player.loaded_chunks.putNoClobber(chunk_id, {});

                const pkt = try packet.S2CChunkDataPacket.init(self.alloc);
                pkt.chunk = self.getChunk(chunk_id);
                pkt.full_chunk = true;
                player.network_handler.sendPacket(try pkt.encode(self.alloc));
                pkt.deinit(self.alloc);
            } else {
                const chunk = try Chunk.initFlat(self.alloc, @bitCast(i32, @truncate(u32, chunk_id >> 32)), @bitCast(i32, @truncate(u32, chunk_id)));
                try self.captureChunk(chunk);
            }
        }

        for (loaded_chunks.items) |chunk_id| {
            const held = player.loaded_chunks_lock.acquire();
            defer held.release();
            try player.loaded_chunks.putNoClobber(chunk_id, {});
        }
    }

    pub fn setBlock(self: *Group, pos: lc_block.BlockPos, block_state: lc_block.BlockState) !bool {
        const chunk_x = @divFloor(pos.x, 16);
        const chunk_z = @divFloor(pos.z, 16);

        var chunk = self.getChunk((@bitCast(u64, @as(i64, chunk_x)) << 32) | @bitCast(u32, chunk_z));
        const changed = try chunk.setBlock(std.math.absCast(@mod(pos.x, 16)), @intCast(u32, pos.y), std.math.absCast(@mod(pos.z, 16)), block_state);
        if (changed) {
            const pkt = try packet.S2CBlockChangePacket.init(self.alloc);
            pkt.position = pos;
            pkt.block_state = block_state;
            try self.sendPacketToAll(try pkt.encode(self.alloc), null);
            pkt.deinit(self.alloc);
            return true;
        } else {
            return false;
        }
    }

    pub fn captureChunk(self: *Group, chunk: *Chunk) !void {
        const held = self.chunks_lock.acquire();
        defer held.release();
        try self.chunks.putNoClobber(chunk.chunkID(), chunk);
    }

    pub fn releaseChunk(self: *Group, id: u64) void {
        const held = self.chunks_lock.acquire();
        defer held.release();
        _ = self.chunks.remove(id);
    }

    pub fn containsChunk(self: *Group, id: u64) bool {
        const held = self.chunks_lock.acquire();
        defer held.release();
        return self.chunks.contains(id);
    }

    pub fn getChunk(self: *Group, id: u64) *Chunk {
        const held = self.chunks_lock.acquire();
        defer held.release();
        return self.chunks.get(id).?;
    }
};
