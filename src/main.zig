const std = @import("std");
const log = std.log;
const heap = std.heap;

pub const io_mode = .evented;

const Server = @import("server.zig").Server;
const l_config = @import("config.zig").config;

pub fn main() !void {
    var gpa: heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    log.info("starting", .{});

    var server = try Server.init(&gpa.allocator, l_config.seed);
    defer server.deinit();

    try server.serve(try std.net.Address.resolveIp(l_config.bind_address, l_config.bind_port));

    var frame = async server.run();
    try await frame;
}
