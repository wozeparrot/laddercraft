const std = @import("std");

const zlm = @import("zlm").specializeOn(f64);

const UUID = @import("../uuid.zig").UUID;

pub const Entity = struct {
    kind: EntityKind,
    uuid: UUID,

    pos: zlm.Vec3,
    look: zlm.Vec2,
    vel: zlm.Vec3,

    last_pos: zlm.Vec3,
    last_look: zlm.Vec2,
    last_vel: zlm.Vec3,

    on_ground: bool,
};

pub const EntityKind = enum {
    player,
};