const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;
const atomic = std.atomic;
const rand = std.rand;

const pike = @import("pike");
const Socket = pike.Socket;
const Notifier = pike.Notifier;

const mc_core = @import("minecart_core");
const network = mc_core.network;
const packet = network.packet;
const UUID = mc_core.UUID;

const Server = @import("server.zig").Server;
const ClientQueue = @import("server.zig").ClientQueue;

pub const Client = struct {
    id: i32,
    frame: @Frame(Client.handle),
    arena: std.heap.ArenaAllocator,

    socket: Socket,
    conn_state: network.client.ConnectionState,

    should_close: atomic.Bool = atomic.Bool.init(false),

    pub fn handle(self: *Client, server: *Server, notifier: *const Notifier) !void {
        // register client on server
        var node = ClientQueue.Node{ .data = self };
        server.clients.put(&node);
        // try to remove client
        defer if (server.clients.remove(&node)) {
            suspend {
                self.socket.deinit();
                self.arena.deinit();
                server.alloc.destroy(self);
            }
        };

        // initialize client variables
        self.conn_state = .handshake;

        // register pike notifier
        try self.socket.registerTo(notifier);

        // reader and writer
        const reader = self.socket.reader();
        const writer = self.socket.writer();

        // main loop
        while (!self.should_close.load(.Unordered)) {
            // decode a basic packet
            const base_pkt = try packet.Packet.decode(&self.arena.allocator, reader);

            // switch on current connection state
            switch (self.conn_state) {
                .handshake, .login => try self.handleHandshake(server, base_pkt, reader, writer),
                .play => try self.handlePlay(server, base_pkt, reader, writer),
                else => {},
            }

            // free the packet
            base_pkt.deinit(&self.arena.allocator);
        }
    }

    // handshake and login start
    fn handleHandshake(self: *Client, server: *Server, base_pkt: *packet.Packet, reader: anytype, writer: anytype) !void {
        switch (base_pkt.id) {
            0x00,
            // switch current connection state
            => switch (self.conn_state) {
                .handshake => {
                    // decode handshake packet
                    const pkt = try packet.C2SHandshakePacket.decodeBase(&self.arena.allocator, base_pkt);
                    std.debug.print("c2s: {}\n", .{pkt});

                    // make sure protocol version matches
                    if (pkt.protocol_version == 754) {
                        // login state
                        self.conn_state = pkt.next_state;
                    } else {
                        self.should_close.store(true, .Unordered);
                    }
                },
                .login => {
                    // decode login start packet
                    const pkt = try packet.C2SLoginStartPacket.decodeBase(&self.arena.allocator, base_pkt);
                    std.debug.print("c2s: {}\n", .{pkt});

                    // send login success packet
                    const spkt = try packet.S2CLoginSuccessPacket.init(&self.arena.allocator);
                    spkt.uuid = UUID.new(&std.rand.DefaultPrng.init(server.seed + @bitCast(u64, std.time.timestamp())).random);
                    spkt.username = pkt.username;
                    try spkt.encode(&self.arena.allocator, writer);
                    std.debug.print("s2c: {}\n", .{spkt});
                    spkt.deinit(&self.arena.allocator);

                    // play state
                    try self.transistionToPlay(server, writer);
                },
                else => {},
            },
            else => log.err("Unknown handshake packet: {}", .{base_pkt}),
        }
    }

    fn transistionToPlay(self: *Client, server: *Server, writer: anytype) !void {
        const spkt = try packet.S2CJoinGamePacket.init(&self.arena.allocator);
        spkt.entity_id = self.id;
        try spkt.encode(&self.arena.allocator, writer);
        std.debug.print("s2c: {}\n", .{spkt});
        spkt.deinit(&self.arena.allocator);

        self.conn_state = .play;
    }

    fn handlePlay(self: *Client, server: *Server, base_pkt: *packet.Packet, reader: anytype, writer: anytype) !void {
        switch (base_pkt.id) {
            else => log.err("Unknown play packet: {}", .{base_pkt}),
        }
    }
};
