const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;

const pike = @import("pike");
const Notifier = pike.Notifier;
const zap = @import("zap");
const sync = @import("../sync.zig");

const ladder_core = @import("ladder_core");
const lc_player = ladder_core.player;
const network = ladder_core.network;
const packet = network.packet;

const NetworkHandler = @import("network_handler.zig").NetworkHandler;
const Group = @import("../group.zig").Group;

pub const Player = struct {
    alloc: *Allocator,

    group: ?*Group,

    network_handler: *NetworkHandler,
    player: lc_player.Player,
    player_lock: sync.Mutex,

    keep_alive: std.time.Timer,

    loaded_chunks: std.AutoArrayHashMap(u64, void),
    loaded_chunks_lock: sync.Mutex,

    pub fn init(alloc: *Allocator, network_handler: *NetworkHandler) !*Player {
        const player = try alloc.create(Player);
        player.* = .{
            .alloc = alloc,

            .group = null,

            .network_handler = network_handler,
            .player = try lc_player.Player.init(alloc),
            .player_lock = sync.Mutex{},

            .keep_alive = try std.time.Timer.start(),

            .loaded_chunks = std.AutoArrayHashMap(u64, void).init(alloc),
            .loaded_chunks_lock = sync.Mutex{},
        };
        return player;
    }

    pub fn deinit(self: *Player) void {
        const held = self.loaded_chunks_lock.acquire();
        self.loaded_chunks.deinit();
        held.release();

        self.alloc.free(self.player.username);
        const player_held = self.player_lock.acquire();
        self.player.deinit();
        player_held.release();

        self.network_handler.deinit();
        self.alloc.destroy(self);
    }

    pub fn start(self: *Player, notifier: *const Notifier) !void {
        try zap.runtime.spawn(.{}, Player.run, .{self, notifier});
    }

    pub fn run(self: *Player, notifier: *const Notifier) void {
        self._run(notifier) catch |err| {
            log.err("player: {}", .{@errorName(err)});
        };
    }

    pub fn _run(self: *Player, notifier: *const Notifier) !void {
        zap.runtime.yield();

        while (self.network_handler.is_alive.load(.Monotonic)) {
            zap.runtime.yield();
            
            if (self.keep_alive.read() > std.time.ns_per_s * 6) {
                var pkt = try packet.S2CKeepAlivePacket.init(self.alloc);
                defer pkt.deinit(self.alloc);
                pkt.id = 0;
                self.network_handler.keep_alive_id.set(pkt.id);
                try self.network_handler.sendPacket(try pkt.encode(self.alloc));
                self.keep_alive.reset();
            }

            try self.group.?.updatePlayerChunks(self);
        }

        if (self.group) |group| {
            const held = group.players_lock.acquire();
            group.players.removeAssertDiscard(self);
            _ = group.player_count.decr();
            held.release();
        }
        self.deinit();
    }
};
