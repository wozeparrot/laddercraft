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

    pub fn init(alloc: *Allocator) !Player {
        const base = try alloc.create(entity.Entity);
        base.* = .{
            .kind = .player,
            .uuid = undefined,

            .pos = zlm.Vec3.zero,
            .look = zlm.Vec2.zero,
            .vel = zlm.Vec3.zero,

            .last_pos = zlm.Vec3.zero,
            .last_look = zlm.Vec2.zero,
            .last_vel = zlm.Vec3.zero,

            .on_ground = true,
        };
        return Player{
            .alloc = alloc,
            .base = base,

            .username = undefined,
        };
    }

    pub fn deinit(self: *Player) void {
        self.alloc.destroy(self.base);
    }

    pub inline fn chunkX(self: *Player) i32 {
        return @floatToInt(i32, self.base.pos.x / 16);
    }

    pub inline fn chunkZ(self: *Player) i32 {
        return @floatToInt(i32, self.base.pos.z / 16);
    }

    pub inline fn lastChunkX(self: *Player) i32 {
        return @floatToInt(i32, self.base.last_pos.x / 16);
    }

    pub inline fn lastChunkZ(self: *Player) i32 {
        return @floatToInt(i32, self.base.last_pos.z / 16);
    }
};