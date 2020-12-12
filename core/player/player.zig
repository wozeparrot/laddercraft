const entity = @import("../entity/entity.zig");

pub const Player = struct {
    base: *entity.Entity,

    username: []const u8,
};