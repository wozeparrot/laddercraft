const std = @import("std");
const log = std.log;
const heap = std.heap;

const pike = @import("pike");
const zap = @import("zap");

const Server = @import("server.zig").Server;

pub const pike_task = zap.runtime.executor.Task;
pub const pike_batch = zap.runtime.executor.Batch;
pub const pike_dispatch = dispatch;

pub const io_mode = .evented;

inline fn dispatch(batchable: anytype, args: anytype) void {
    zap.runtime.schedule(batchable, args);
}

pub fn main() anyerror!void {
    try try zap.runtime.run(.{}, asyncMain, .{});
}

pub fn asyncMain() !void {
    const notifier = try pike.Notifier.init();
    defer notifier.deinit();

    var stopped = false;
    log.info("starting", .{});

    var frame = async run(&notifier, &stopped);

    while (!stopped) {
        try notifier.poll(1_000_000);
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
