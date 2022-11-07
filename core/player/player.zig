const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const zlm = @import("zlm").SpecializeOn(f64);

const entity = @import("../entity/entity.zig");
const UUID = @import("../uuid.zig").UUID;

pub const inventory = @import("inventory.zig");
const Inventory = inventory.Inventory;

pub const Player = struct {
    alloc: Allocator,
    base: *entity.Entity,

    username: []const u8,

    last_chunk_x: i32,
    last_chunk_z: i32,

    inventory: Inventory,
    selected_hotbar_slot: u8,

    pub fn init(alloc: Allocator) !Player {
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

            .inventory = Inventory{},
            .selected_hotbar_slot = 0,
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

    /// Checks if a point will collide with the player
    pub fn checkCollision(self: *Player, p: zlm.Vec3) bool {
        if (p.x + 0.5 < self.base.pos.x + 0.5 and p.x + 0.5 > self.base.pos.x - 0.5 and
            p.z + 0.5 < self.base.pos.z + 0.5 and p.z + 0.5 > self.base.pos.z - 0.5 and
            p.y + 0.0 < self.base.pos.y + 2.0 and p.y + 0.0 > self.base.pos.y - 0.0) return true;
        return false;
    }
};
