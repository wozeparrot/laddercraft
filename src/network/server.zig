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

const Client = @import("client.zig").Client;
pub const ClientQueue = std.atomic.Queue(*Client);

pub const Server = struct {
    frame: @Frame(Server.run),
    alloc: *Allocator,

    seed: u64,
    random: rand.Random,

    socket: Socket,

    clients: ClientQueue,
    current_client_id: i32 = 0,

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
            .clients = ClientQueue.init(),
        };
    }

    pub fn deinit(self: *Server) void {
        self.socket.deinit();

        await self.frame;

        while (self.clients.get()) |node| {
            const client = node.data;
            
            client.socket.deinit();
            client.arena.deinit();
            await client.frame catch |err| {
                log.err("{} when awaiting client frame!", .{@errorName(err)});
            };
            self.alloc.destroy(node.data);
        }
    }

    pub fn serve(self: *Server, notifier: *const Notifier, address: net.Address) !void {
        try self.socket.bind(address);
        try self.socket.listen(128);
        try self.socket.registerTo(notifier);

        self.frame = async self.run(notifier);
    }

    fn run(self: *Server, notifier: *const Notifier) void {
        while (true) {
            var conn = self.socket.accept() catch |err| switch (err) {
                error.SocketNotListening,
                error.OperationCancelled,
                => return,
                else => {
                    continue;
                },
            };

            const client = self.alloc.create(Client) catch |err| {
                conn.socket.deinit();
                continue;
            };

            client.id = self.current_client_id;
            self.current_client_id += 1;
            client.arena = std.heap.ArenaAllocator.init(self.alloc);
            client.socket = conn.socket;
            client.frame = async client.handle(self, notifier);

            // self.clients.put(.{ .data = client });
        }
    }
};
