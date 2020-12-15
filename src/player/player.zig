const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;

const pike = @import("pike");
const Notifier = pike.Notifier;
const zap = @import("zap");

const ladder_core = @import("ladder_core");
const lc_player = ladder_core.player;

const NetworkHandler = @import("network_handler.zig").NetworkHandler;
const Group = @import("../group.zig").Group;

pub const Player = struct {
    alloc: *Allocator,

    group: ?*Group,

    network_handler: *NetworkHandler,
    player: lc_player.Player,

    is_alive: std.atomic.Bool,
    keep_alive: std.time.Timer,

    pub fn init(alloc: *Allocator, network_handler: *NetworkHandler) !*Player {
        const player = try alloc.create(Player);
        player.* = .{
            .alloc = alloc,

            .group = null,

            .network_handler = network_handler,
            .player = undefined,

            .is_alive = std.atomic.Bool.init(true),
            .keep_alive = try std.time.Timer.start(),
        };
        return player;
    }

    pub fn deinit(self: *Player) void {
        self.is_alive.store(false, .SeqCst);

        self.network_handler.deinit();

        self.alloc.destroy(self);
    }

    pub fn start(self: *Player, notifier: *const Notifier) !void {
        self.is_alive.store(true, .SeqCst);
        
        try zap.runtime.spawn(.{}, Player.run, .{self, notifier});
    }

    pub fn run(self: *Player, notifier: *const Notifier) void {
        self._run(notifier) catch |err| {
            log.err("player: {}", .{@errorName(err)});
        };
    }

    pub fn _run(self: *Player, notifier: *const Notifier) !void {
        while (self.is_alive.load(.SeqCst)) {
            if (self.keep_alive.read() > std.time.ns_per_s) {
                
            }
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
