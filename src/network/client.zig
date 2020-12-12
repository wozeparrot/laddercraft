const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const log = std.log;
const atomic = std.atomic;

const pike = @import("pike");
const Socket = pike.Socket;
const Notifier = pike.Notifier;

const mc_core = @import("minecart_core");
const network = mc_core.network;
const packet = network.packet;

const Server = @import("server.zig").Server;
const ClientQueue = @import("server.zig").ClientQueue;

pub const Client = struct {
    frame: @Frame(Client.handle),
    arena: std.heap.ArenaAllocator,

    socket: Socket,
    conn_state: network.client.ConnectionState,

    should_close: atomic.Bool = atomic.Bool.init(false),

    pub fn handle(self: *Client, server: *Server, notifier: *const Notifier) !void {
        var node = ClientQueue.Node{ .data = self };
        server.clients.put(&node);
        defer if (server.clients.remove(&node)) {
            suspend {
                self.socket.deinit();
                self.arena.deinit();
                server.alloc.destroy(self);
            }
        };

        self.conn_state = .handshake;

        try self.socket.registerTo(notifier);

        const reader = self.socket.reader();
        const writer = self.socket.writer();
        while (!self.should_close.load(.Unordered)) {
            const base_pkt = try packet.Packet.decode(&self.arena.allocator, reader);

            switch (base_pkt.id) {
                0 => {
                    switch (self.conn_state) {
                        .handshake => {
                            const pkt = try packet.C2SHandshakePacket.decodeBase(&self.arena.allocator, base_pkt);
                            std.debug.print("{}\n", .{pkt});

                            if (pkt.protocol_version == 754) {
                                self.conn_state = pkt.next_state;
                            } else {
                                self.should_close.store(true, .Unordered);
                            }

                            pkt.deinit(&self.arena.allocator);
                        },
                        .login => {
                            const pkt = try packet.C2SLoginStartPacket.decodeBase(&self.arena.allocator, base_pkt);
                            std.debug.print("{}\n", .{pkt});

                            const spkt = try packet.S2CLoginSuccessPacket.init(&self.arena.allocator);
                            spkt.uuid = 0x3a564e543ef642c0a3b1ad28322d8f64;
                            spkt.username = pkt.username;
                            try spkt.encode(&self.arena.allocator, writer);
                            spkt.deinit(&self.arena.allocator);

                            pkt.deinit(&self.arena.allocator);
                        },
                        else => {},
                    }
                },
                else => {
                    std.debug.print("{}\n", .{base_pkt});
                    base_pkt.deinit(&self.arena.allocator);
                },
            }
        }
    }
};