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

    socket: Socket,
    current_network_id: i32,

    groups: std.AutoArrayHashMap(*Group, void),
    groups_lock: std.Mutex,

    is_alive: std.atomic.Bool,

    pub fn init(alloc: *Allocator, seed: u64) !Server {
        var socket = try Socket.init(c.AF_INET, c.SOCK_STREAM, c.IPPROTO_TCP, 0);
        errdefer socket.deinit();

        try socket.set(.reuse_address, true);

        return Server{
            .frame = undefined,
            .alloc = alloc,

            .seed = seed,
            .random = rand.DefaultPrng.init(seed).random,

            .socket = socket,
            .current_network_id = 0,

            .groups = std.AutoArrayHashMap(*Group, void).init(alloc),
            .groups_lock = std.Mutex{},

            .is_alive = std.atomic.Bool.init(false),
        };
    }

    pub fn deinit(self: *Server) void {
        self.socket.deinit();

        await self.frame catch |err| {
            log.err("{} while awaiting server frame!", .{@errorName(err)});
        };

        const held = self.groups_lock.acquire();
        for (self.groups.items()) |entry| {
            std.debug.print("deinit group from server", .{});
            entry.key.deinit();
            self.alloc.destroy(entry.key);
        }
        self.groups.deinit();
    }

    pub fn serve(self: *Server, notifier: *const Notifier, address: net.Address) !void {
        try self.socket.bind(address);
        try self.socket.listen(128);
        try self.socket.registerTo(notifier);

        self.frame = async self.run(notifier);
    }

    // main async loop
    fn run(self: *Server, notifier: *const Notifier) !void {
        // spawn gc
        try zap.runtime.spawn(.{}, Server.gc, .{self});

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

            // register socket to notifier
            try conn.socket.registerTo(notifier);
            // try handshake with client
            if (self.handleHandshake(notifier, &conn.socket) catch |err| {
                conn.socket.deinit();
                continue;
            }) {
                // create player and player network handler
                const network_handler = try NetworkHandler.init(self.alloc, conn.socket, self.current_network_id);
                self.current_network_id += 1;
                const player = try Player.init(self.alloc, network_handler);

                // get groups lock
                const held = self.groups_lock.acquire();
                defer held.release();
                // create new group if one does not exist
                if (self.groups.count() == 0) {
                    var group = try Group.init(self.alloc, self, notifier);
                    // add player to group
                    group.addPlayer(player) catch |err| {
                        conn.socket.deinit();
                        self.alloc.destroy(player);
                    };
                    // start group
                    group.start();
                    try self.groups.put(group, {});
                // join existing group
                } else {
                    // find best group and put player in it
                    for (self.groups.items()) |entry| {
                        entry.key.addPlayer(player) catch |err| {
                            conn.socket.deinit();
                            self.alloc.destroy(player);
                            continue;
                        };
                        break;
                    }
                }
            } else {
                conn.socket.deinit();
                continue;
            }
        }
    }

    // handle handshake and login before creating a player
    fn handleHandshake(self: *Server, notifier: *const Notifier, socket: *Socket) !bool {
        const reader = socket.reader();
        const writer = socket.writer();

        // current connection state
        var conn_state: lc_ConnectionState = .handshake;

        // loop until we reach play state or close the connection
        while (true) {
            const base_pkt = try lc_packet.Packet.decode(self.alloc, reader);

            switch (base_pkt.id) {
                0x00 => switch (conn_state) {
                    .handshake => {
                        // decode handshake packet
                        const pkt = try lc_packet.C2SHandshakePacket.decodeBase(self.alloc, base_pkt);
                        defer pkt.deinit(self.alloc);
                        log.debug("{}\n", .{pkt});

                        // make sure protocol version matches
                        if (pkt.protocol_version == 754) {
                            // login state
                            conn_state = pkt.next_state;
                        } else {
                            const spkt = try lc_packet.S2CLoginDisconnectPacket.init(self.alloc);
                            defer spkt.deinit(self.alloc);
                            spkt.reason = .{ .text = "Protocol version mismatch!" };
                            try spkt.encode(self.alloc, writer);
                            log.debug("{}\n", .{spkt});

                            return false;
                        }
                    },
                    .login => {
                        // decode login start packet
                        const pkt = try lc_packet.C2SLoginStartPacket.decodeBase(self.alloc, base_pkt);
                        defer pkt.deinit(self.alloc);
                        log.debug("{}\n", .{pkt});

                        // send login success packet
                        const spkt = try lc_packet.S2CLoginSuccessPacket.init(self.alloc);
                        defer spkt.deinit(self.alloc);
                        spkt.uuid = UUID.new(&std.rand.DefaultPrng.init(@bitCast(u64, std.time.timestamp())).random);
                        spkt.username = pkt.username;
                        try spkt.encode(self.alloc, writer);
                        log.debug("{}\n", .{spkt});

                        return true;
                    },
                    .status => {
                        base_pkt.deinit(self.alloc);
                        return false;
                    },
                    else => {
                        base_pkt.deinit(self.alloc);
                        return false;
                    },
                },
                else => {
                    log.err("Unknown handshake packet: {}", .{base_pkt});
                    base_pkt.deinit(self.alloc);
                    return false;
                },
            }
        }
    }

    // gc dead players and empty groups
    fn gc(self: *Server) void {
        var timer = std.time.Timer.start() catch unreachable;

        while (self.is_alive.load(.SeqCst)) {
            if (timer.read() >= std.time.ns_per_s) {
                const held = self.groups_lock.acquire();
                for (self.groups.items()) |entry| {
                    entry.key.gc();
                    if (!entry.key.is_alive.load(.SeqCst)) {
                        self.groups.removeAssertDiscard(entry.key);
                        entry.key.deinit();
                    }
                }
                held.release();
                std.debug.print("\ngc\n", .{});
            }
        }
    }
};
