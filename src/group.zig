const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;

const pike = @import("pike");
const Notifier = pike.Notifier;
const zap = @import("zap");

const ladder_core = @import("ladder_core");
const network = ladder_core.network;
const packet = network.packet;
const Chunk = ladder_core.world.chunk.Chunk;

const Server = @import("server.zig").Server;
const Player = @import("player/player.zig").Player;
const l_config = @import("config.zig").config;

pub const Group = struct {
    alloc: *Allocator,

    server: *Server,
    notifier: *const Notifier,

    players: std.AutoArrayHashMap(*Player, void),
    players_lock: std.Mutex,
    player_count: std.atomic.Int(u32),

    chunks: std.AutoArrayHashMap(u64, *Chunk),
    chunks_lock: std.Mutex,

    is_alive: std.atomic.Bool,

    pub fn init(alloc: *Allocator, server: *Server, notifier: *const Notifier) !*Group {
        const group = try alloc.create(Group);
        group.* = .{
            .alloc = alloc,

            .server = server,
            .notifier = notifier,

            .players = std.AutoArrayHashMap(*Player, void).init(alloc),
            .players_lock = std.Mutex{},
            .player_count = std.atomic.Int(u32).init(0),

            .chunks = std.AutoArrayHashMap(u64, *Chunk).init(alloc),
            .chunks_lock = std.Mutex{},

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
        try zap.runtime.spawn(.{}, Group.run, .{self});
    }

    pub fn run(self: *Group) void {
        self._run() catch |err| {
            log.err("group - run(): {}", .{@errorName(err)});
        };
    }

    pub fn _run(self: *Group) !void {
        zap.runtime.yield();

        while (self.is_alive.load(.SeqCst)) {
            zap.runtime.yield();

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

    pub fn removePlayer(self: *Group, player: *Player) void {
        const held = self.players_lock.acquire();
        defer held.release();

        _ = self.player_count.decr();
        _ = self.players.remove(player);
    }

    pub fn updatePlayerChunks(self: *Group, player: *Player) !void {
        var needed_chunks = std.ArrayList(u64).init(self.alloc);
        defer needed_chunks.deinit();

        const inner_player_held = player.player_lock.acquire();
        const chunk_x = player.player.chunkX();
        const chunk_z = player.player.chunkZ();
        const last_chunk_x = player.player.lastChunkX();
        const last_chunk_z = player.player.lastChunkZ();
        inner_player_held.release();

        var x: i32 = chunk_x - @as(i32, l_config.view_distance);
        while (x < chunk_x + @as(i32, l_config.view_distance)) : (x += 1) {
            var z: i32 = chunk_z - @as(i32, l_config.view_distance);
            while (z < chunk_z + @as(i32, l_config.view_distance)) : (z += 1) {
                zap.runtime.yield();

                const held = player.loaded_chunks_lock.acquire();
                defer held.release();
                const chunk_id = (@bitCast(u64, @as(i64, x)) << 32) | @bitCast(u32, z);
                if (!player.loaded_chunks.contains(chunk_id)) {
                    try needed_chunks.append(chunk_id);
                } else {
                    // player.loaded_chunks.removeAssertDiscard(chunk_id);
                }
            }
        }

        // const chunks_held = player.loaded_chunks_lock.acquire();
        // for (player.loaded_chunks.items()) |entry| {           
        //     const pkt = try packet.S2CUnloadChunkPacket.init(self.alloc);
        //     pkt.chunk_x = @bitCast(i32, @truncate(u32, entry.key >> 32));
        //     pkt.chunk_z = @bitCast(i32, @truncate(u32, entry.key));
        //     try player.network_handler.sendPacket(try pkt.encode(self.alloc));
        //     pkt.deinit(self.alloc);
        //     player.loaded_chunks.removeAssertDiscard(entry.key);
        // }
        // chunks_held.release();

        for (needed_chunks.items) |chunk_pos| {
            zap.runtime.yield();

            const held = self.chunks_lock.acquire();
            defer held.release();
            if (self.chunks.contains(chunk_pos)) {
                const player_held = player.loaded_chunks_lock.acquire();
                defer player_held.release();
                // try player.loaded_chunks.putNoClobber(chunk_pos, {});

                const pkt = try packet.S2CChunkDataPacket.init(self.alloc);
                pkt.chunk = self.chunks.get(chunk_pos).?;
                pkt.full_chunk = true;
                try player.network_handler.sendPacket(try pkt.encode(self.alloc));
                pkt.deinit(self.alloc);
            } else {
                const chunk = try Chunk.initFlat(self.alloc, @bitCast(i32, @truncate(u32, chunk_pos >> 32)), @bitCast(i32, @truncate(u32, chunk_pos)));
                try self.chunks.put(chunk_pos, chunk);
                log.debug("generated chunk at {}, {}", .{chunk.x, chunk.z});
            }
        }

        if (chunk_x != last_chunk_x or chunk_z != last_chunk_z) {
            const pkt = try packet.S2CUpdateViewPositionPacket.init(self.alloc);
            pkt.chunk_x = chunk_x;
            pkt.chunk_z = chunk_z;
            try player.network_handler.sendPacket(try pkt.encode(self.alloc));
            pkt.deinit(self.alloc);
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
        return self.chunks.contains(id);
    }
};
