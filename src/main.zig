const std = @import("std");
const log = std.log;
const heap = std.heap;

const pike = @import("pike");
const snow = @import("snow");

const Server = @import("network/server.zig").Server;

pub const io_mode = .evented;

pub fn main() anyerror!void {
    const notifier = try pike.Notifier.init();
    defer notifier.deinit();

    var stopped = false;
    log.info("starting", .{});

    var frame = async run(&notifier, &stopped);

    while (!stopped) {
        try notifier.poll(1000);
    }

    try nosuspend await frame;

    log.info("stopped", .{});    
}

pub fn run(notifier: *const pike.Notifier, stopped: *bool) !void {
    var gpa: heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    var event = try pike.Event.init();
    defer event.deinit();

    try event.registerTo(notifier);

    var signal = try pike.Signal.init(.{ .interrupt = true });
    defer signal.deinit();

    defer {
        stopped.* = true;
        event.post() catch unreachable;
    }

    var server = try Server.init(&gpa.allocator, 1337);
    defer server.deinit();

    try server.serve(notifier, try std.net.Address.resolveIp("0.0.0.0", 25565));
    try signal.wait();
}
