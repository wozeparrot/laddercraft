const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;

const pike = @import("pike");
const Notifier = pike.Notifier;

const ladder_core = @import("ladder_core");
const Chunk = ladder_core.world.chunk.Chunk;

const Server = @import("server.zig").Server;
const Player = @import("player/player.zig").Player;

pub const Group = struct {
    const Players = std.atomic.Queue(*Player);

    frame: @Frame(Group.run),
    alloc: *Allocator,

    server: *Server,
    notifier: *const Notifier,

    players: std.AutoArrayHashMap(*Player, void),
    players_lock: std.Mutex,
    player_count: std.atomic.Int(u32),
    chunks: std.AutoHashMap(u64, Chunk),

    is_alive: std.atomic.Bool,

    pub fn init(alloc: *Allocator, server: *Server, notifier: *const Notifier) !*Group {
        const group = try alloc.create(Group);
        group.* = .{
            .frame = undefined,
            .alloc = alloc,

            .server = server,
            .notifier = notifier,

            .players = std.AutoArrayHashMap(*Player, void).init(alloc),
            .players_lock = std.Mutex{},
            .player_count = std.atomic.Int(u32).init(0),
            .chunks = std.AutoHashMap(u64, Chunk).init(alloc),

            .is_alive = std.atomic.Bool.init(true),
        };
        return group;
    }

    pub fn deinit(self: *Group) void {
        self.is_alive.store(false, .SeqCst);

        await self.frame catch |err| {
            log.err("{} while awaiting group frame!", .{@errorName(err)});
        };

        const held = self.players_lock.acquire();
        for (self.players.items()) |entry| {
            entry.key.deinit();
            self.alloc.destroy(entry.key);
        }
        self.players.deinit();
        self.chunks.deinit();
    }

    pub fn start(self: *Group) void {
        self.is_alive.store(true, .SeqCst);
        self.frame = async self.run();
    }

    pub fn run(self: *Group) !void {
        while (self.is_alive.load(.SeqCst)) {
            if (self.player_count.get() == 0) {
                self.is_alive.store(false, .SeqCst);
            }
        }
    }

    pub fn addPlayer(self: *Group, player: *Player) !void {
        const held = self.players_lock.acquire();
        defer held.release();

        _ = self.player_count.incr();
        try self.players.put(player, {});

        player.group = self;
        player.start(self.notifier);
    }

    pub fn removePlayer(self: *Group, player: *Player) void {
        const held = self.players_lock.acquire();
        defer held.release();

        _ = self.player_count.decr();
        _ = self.players.remove(player);
    }

    pub fn gc(self: *Group) void {
        // remove dead players
        const held = self.players_lock.acquire();
        for (self.players.items()) |entry| {
            if (!entry.key.is_alive.load(.SeqCst)) {
                self.players.removeAssertDiscard(entry.key);
                _ = self.player_count.decr();
                entry.key.deinit();
            }
        }
        held.release();
    }

    pub fn containsChunk(self: *Group, x: i32, z: i32) bool {
        return self.chunks.contains((x << 32) | z);
    }
};
