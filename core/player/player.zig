const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const zlm = @import("zlm").specializeOn(f64);

const entity = @import("../entity/entity.zig");
const UUID = @import("../uuid.zig").UUID;

pub const Player = struct {
    alloc: *Allocator,
    base: *entity.Entity,

    username: []const u8,

    last_chunk_x: i32,
    last_chunk_z: i32,

    pub fn init(alloc: *Allocator) !Player {
        const base = try alloc.create(entity.Entity);
        base.* = .{
            .kind = .player,
            .uuid = undefined,
            .entity_id = -1,

            .pos = zlm.vec3(0, 5, 0),
            .look = zlm.Vec2.zero,
            .vel = zlm.Vec3.zero,

            .last_pos = zlm.vec3(0, 5, 0),
            .last_look = zlm.Vec2.zero,
            .last_vel = zlm.Vec3.zero,

            .on_ground = true,
        };
        return Player{
            .alloc = alloc,
            .base = base,

            .username = undefined,

            .last_chunk_x = 0,
            .last_chunk_z = 0,
        };
    }

    pub fn deinit(self: *Player) void {
        self.alloc.destroy(self.base);
    }

    pub inline fn chunkX(self: *Player) i32 {
        return @divFloor(@floatToInt(i32, self.base.pos.x), 16);
    }

    pub inline fn chunkZ(self: *Player) i32 {
        return @divFloor(@floatToInt(i32, self.base.pos.z), 16);
    }
};