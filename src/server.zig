const std = @import("std");
const rand = std.rand;
const mem = std.mem;
const Allocator = mem.Allocator;
const c = std.c;
const log = std.log;
const net = std.net;

const ladder_core = @import("ladder_core");
const lc_packet = ladder_core.network.packet;
const lc_ConnectionState = ladder_core.network.client.ConnectionState;
const UUID = ladder_core.UUID;

const Player = @import("player/player.zig").Player;
const NetworkHandler = @import("player/network_handler.zig").NetworkHandler;
const Group = @import("group.zig").Group;

pub const Server = struct {
    frame: @Frame(Server.run),
    alloc: *Allocator,

    seed: u64,
    random: rand.Random,
    current_entity_id: std.atomic.Int(i32),

    stream_server: net.StreamServer,
    holding: std.AutoArrayHashMap(*NetworkHandler, void),
    holding_lock: std.event.Lock,

    groups: std.AutoArrayHashMap(*Group, void),
    groups_lock: std.event.Lock,

    is_alive: std.atomic.Bool,

    pub fn init(alloc: *Allocator, seed: u64) !Server {
        return Server{
            .frame = undefined,
            .alloc = alloc,

            .seed = seed,
            .random = rand.DefaultPrng.init(seed).random,
            .current_entity_id = std.atomic.Int(i32).init(0),

            .stream_server = net.StreamServer.init(.{ .reuse_address = true }),
            .holding = std.AutoArrayHashMap(*NetworkHandler, void).init(alloc),
            .holding_lock = std.event.Lock{},

            .groups = std.AutoArrayHashMap(*Group, void).init(alloc),
            .groups_lock = std.event.Lock{},

            .is_alive = std.atomic.Bool.init(true),
        };
    }

    pub fn deinit(self: *Server) void {
        self.is_alive.store(false, .SeqCst);

        self.stream_server.deinit();

        const groups_held = self.groups_lock.acquire();
        for (self.groups.items()) |entry| {
            entry.key.deinit();
        }
        groups_held.release();
        self.groups.deinit();

        const holding_held = self.holding_lock.acquire();
        for (self.holding.items()) |entry| {
            entry.key.deinit();
        }
        holding_held.release();
        self.holding.deinit();
    }

    // start listening on an address
    pub fn serve(self: *Server, address: net.Address) !void {
        try self.stream_server.listen(address);
    }

    // main async loop
    pub fn run(self: *Server) !void {
        // connection loop
        while (true) {
            var conn = self.stream_server.accept() catch |err| switch (err) {
                error.SocketNotListening => return,
                else => continue,
            };

            // create network_handler
            const network_handler = NetworkHandler.init(self.alloc, conn) catch |err| {
                conn.file.close();
                continue;
            };

            // add to holding group
            const held = self.holding_lock.acquire();
            try self.holding.put(network_handler, {});
            held.release();

            network_handler.start(self) catch |err| {
                conn.file.close();
                continue;
            };
        }
    }

    // transfers a player from one group to another
    pub fn transferToGroup(self: *Server, player: *Player, group: *Group) !void {
        if (player.group) |old_group| {
            old_group.removePlayer(player);
            try group.addPlayer(player);
        } else {
            try group.addPlayer(player);
        }
    }

    // chooses the best group to put a new playing in
    pub fn findBestGroup(self: *Server, player: *Player) !void {
        const held = self.groups_lock.acquire();
        defer held.release();

        if (self.groups.count() == 0) {
            var group = try Group.init(self.alloc, self);
            try group.addPlayer(player);
            try group.start();
            try self.groups.put(group, {});
        } else {
            for (self.groups.items()) |entry| {
                try entry.key.addPlayer(player);
                break;
            }
        }
    }

    pub fn sendPacketToAll(self: *Server, pkt: *lc_packet.Packet, player: ?*Player) !void {
        const held = self.groups_lock.acquire();
        defer held.release();

        for (self.groups.items()) |entry| {
            try entry.key.sendPacketToAll(pkt, player);
        }
    }

    pub fn sendPlayersToPlayer(self: *Server, player: *Player) !void {
        const held = self.groups_lock.acquire();
        defer held.release();

        for (self.groups.items()) |entry| {
            try entry.key.sendPlayersToPlayer(player);
        }
    }

    pub fn nextEntityId(self: *Server) i32 {
        return self.current_entity_id.incr();
    }
};
