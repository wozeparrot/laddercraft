const std = @import("std");

const zlm = @import("zlm").specializeOn(f64);

const UUID = @import("../uuid.zig").UUID;

pub const Entity = struct {
    type: EntityType,
    uuid: UUID,

    pos: zlm.Vec3,
    look: zlm.Vec2,
    vel: zlm.Vec3,
};

pub const EntityType = enum {
    player,
};