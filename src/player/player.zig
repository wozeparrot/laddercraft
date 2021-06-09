const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;

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
    player_lock: std.event.Lock,

    keep_alive: std.time.Timer,

    loaded_chunks: std.AutoArrayHashMap(u64, void),
    loaded_chunks_lock: std.event.Lock,

    pub fn init(alloc: *Allocator, network_handler: *NetworkHandler) !*Player {
        const player = try alloc.create(Player);
        player.* = .{
            .alloc = alloc,

            .group = null,

            .network_handler = network_handler,
            .player = try lc_player.Player.init(alloc),
            .player_lock = std.event.Lock{},

            .keep_alive = try std.time.Timer.start(),

            .loaded_chunks = std.AutoArrayHashMap(u64, void).init(alloc),
            .loaded_chunks_lock = std.event.Lock{},
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

    pub fn start(self: *Player) !void {
        // send player info to all players on server
        const pkt = try packet.S2CPlayerInfoPacket.init(self.alloc);
        pkt.action = .add_player;
        pkt.players = &[_]packet.S2CPlayerInfoPlayer{.{ .uuid = self.player.base.uuid, .data = .{ .add_player = .{
            .name = self.player.username,
            .properties = &[0]packet.S2CPlayerInfoProperties{},
            .gamemode = 0,
            .ping = 0,
            .display_name = null,
        } } }};
        log.debug("{}", .{pkt});
        try self.group.?.server.sendPacketToAll(try pkt.encode(self.alloc), null);
        pkt.deinit(self.alloc);

        const pkt2 = try packet.S2CSpawnPlayerPacket.init(self.alloc);
        pkt2.entity_id = self.player.base.entity_id;
        pkt2.uuid = self.player.base.uuid;
        pkt2.pos = self.player.base.pos;
        pkt2.look = self.player.base.look;
        log.debug("{}", .{pkt2});
        try self.group.?.server.sendPacketToAll(try pkt2.encode(self.alloc), self);
        pkt2.deinit(self.alloc);

        // get player info from other players
        try self.group.?.server.sendPlayersToPlayer(self);

        try std.event.Loop.instance.?.runDetached(self.alloc, Player.run, .{self});
    }

    pub fn run(self: *Player) void {
        self._run() catch |err| {
            log.err("player: {s}", .{@errorName(err)});
        };
    }

    pub fn _run(self: *Player) !void {
        while (self.network_handler.is_alive.load(.Monotonic)) {
            if (self.keep_alive.read() > std.time.ns_per_s * 6) {
                var pkt = try packet.S2CKeepAlivePacket.init(self.alloc);
                defer pkt.deinit(self.alloc);
                pkt.id = 0;
                self.network_handler.keep_alive_id.store(pkt.id, .Monotonic);
                self.network_handler.sendPacket(try pkt.encode(self.alloc));
                self.keep_alive.reset();
            }

            try self.group.?.updatePlayerChunks(self);
        }

        if (self.group) |group| {
            try group.removePlayer(self);
        }
        self.deinit();
    }
};
