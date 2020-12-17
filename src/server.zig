const std = @import("std");
const rand = std.rand;
const mem = std.mem;
const Allocator = mem.Allocator;
const c = std.c;
const log = std.log;
const net = std.net;

const pike = @import("pike");
const Socket = pike.Socket;
const Notifier = pike.Notifier;
const zap = @import("zap");

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

    notifier: *const Notifier,
    socket: Socket,
    current_network_id: i32,
    holding: std.AutoArrayHashMap(*NetworkHandler, void),
    holding_lock: std.Mutex,

    groups: std.AutoArrayHashMap(*Group, void),
    groups_lock: std.Mutex,

    is_alive: std.atomic.Bool,

    pub fn init(alloc: *Allocator, notifier: *const Notifier, seed: u64) !Server {
        var socket = try Socket.init(c.AF_INET, c.SOCK_STREAM, c.IPPROTO_TCP, 0);
        errdefer socket.deinit();

        try socket.set(.reuse_address, true);

        return Server{
            .frame = undefined,
            .alloc = alloc,

            .seed = seed,
            .random = rand.DefaultPrng.init(seed).random,

            .notifier = notifier,
            .socket = socket,
            .current_network_id = 0,
            .holding = std.AutoArrayHashMap(*NetworkHandler, void).init(alloc),
            .holding_lock = std.Mutex{},

            .groups = std.AutoArrayHashMap(*Group, void).init(alloc),
            .groups_lock = std.Mutex{},

            .is_alive = std.atomic.Bool.init(true),
        };
    }

    pub fn deinit(self: *Server) void {
        self.is_alive.store(false, .SeqCst);

        self.socket.deinit();

        await self.frame catch |err| {
            log.err("{} while awaiting server frame!", .{@errorName(err)});
        };

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

    pub fn serve(self: *Server, address: net.Address) !void {
        try self.socket.bind(address);
        try self.socket.listen(128);
        try self.socket.registerTo(self.notifier);

        self.frame = async self.run();
    }

    // main async loop
    fn run(self: *Server) !void {
        // connection loop
        while (true) {
            var conn = self.socket.accept() catch |err| switch (err) {
                error.SocketNotListening,
                error.OperationCancelled,
                => return,
                else => {
                    continue;
                },
            };

            // create network_handler
            const network_handler = NetworkHandler.init(self.alloc, conn.socket, self.current_network_id) catch |err| {
                conn.socket.deinit();
                continue;
            };
            self.current_network_id += 1;
            
            // add to holding group
            const held = self.holding_lock.acquire();
            try self.holding.put(network_handler, {});
            held.release();

            network_handler.start(self) catch |err| {
                conn.socket.deinit();
                continue;
            };
        }
    }

    pub fn transferToGroup(self: *Server, player: *Player, group: *Group) !void {
        if (player.group) |old_group| {
            old_group.removePlayer(player);
            try group.addPlayer(player);
        } else {
            try group.addPlayer(player);
        }
    }

    pub fn findBestGroup(self: *Server, player: *Player) !void {
        const held = self.groups_lock.acquire();
        defer held.release();

        if (self.groups.count() == 0) {
            var group = try Group.init(self.alloc, self, self.notifier);
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
};
