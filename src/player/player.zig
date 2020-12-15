const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const pike = @import("pike");
const Notifier = pike.Notifier;

const ladder_core = @import("ladder_core");
const lc_player = ladder_core.player;

const NetworkHandler = @import("network_handler.zig").NetworkHandler;
const Group = @import("../group.zig").Group;

pub const Player = struct {
    frame: @Frame(Player.run),
    alloc: *Allocator,

    group: *Group,

    network_handler: *NetworkHandler,
    player: lc_player.Player,

    is_alive: std.atomic.Bool,
    watchdog: std.time.Timer,

    pub fn init(alloc: *Allocator, network_handler: *NetworkHandler) !*Player {
        const player = try alloc.create(Player);
        player.* = .{
            .frame = undefined,
            .alloc = alloc,

            .group = undefined,

            .network_handler = network_handler,
            .player = undefined,

            .is_alive = std.atomic.Bool.init(true),
            .watchdog = try std.time.Timer.start()
        };
        return player;
    }

    pub fn deinit(self: *Player) void {
        self.is_alive.store(false, .SeqCst);

        self.network_handler.deinit();
        self.alloc.destroy(self.network_handler);

        await self.frame catch |err| {
            log.err("{} while awaiting player frame!", .{@errorName(err)});
        };
    }

    pub fn start(self: *Player, notifier: *const Notifier) void {
        self.is_alive.store(true, .SeqCst);
        self.network_handler.start(self);
        self.frame = async self.run(notifier);
    }

    pub fn run(self: *Player, notifier: *const Notifier) !void {
        while (self.is_alive.load(.SeqCst)) {
            if (self.watchdog.read() > std.time.ns_per_s * 10) {
                self.is_alive.store(false, .SeqCst);
            }
        }
    }
};
