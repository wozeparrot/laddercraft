const std = @import("std");
const net = std.net;

pub const config: Config = .{
    .bind_address = "0.0.0.0",
    .bind_port = 25565,

    .view_distance = 4,
    .seed = 1337,

    .max_group_size = 10,
};

pub const Config = struct {
    bind_address: []const u8,
    bind_port: u16,

    view_distance: u8,
    seed: u64,

    max_group_size: u32,
};