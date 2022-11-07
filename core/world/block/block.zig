const std = @import("std");

const zlm = @import("zlm").SpecializeOn(f64);

pub usingnamespace @import("block_state.zig");
pub usingnamespace @import("block_entity.zig");

pub const BlockPos = struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn fromVec3(vec: zlm.Vec3) BlockPos {
        return BlockPos{
            .x = @floatToInt(i32, vec.x),
            .y = @floatToInt(i32, vec.y),
            .z = @floatToInt(i32, vec.z),
        };
    }

    pub fn toVec3(self: BlockPos) zlm.Vec3 {
        return zlm.Vec3{
            .x = @intToFloat(f64, self.x),
            .y = @intToFloat(f64, self.y),
            .z = @intToFloat(f64, self.z),
        };
    }

    pub fn fromPacketPosition(position: u64) BlockPos {
        const x = @bitCast(i32, @truncate(u32, position >> 38));
        const y = @bitCast(i32, @truncate(u32, position & 0xFFF));
        const z = @bitCast(i32, @truncate(u32, position << 26 >> 38));
        return BlockPos{
            .x = if (x >= std.math.pow(i32, 2, 25)) x - std.math.pow(i32, 2, 26) else x,
            .y = if (y >= std.math.pow(i32, 2, 11)) y - std.math.pow(i32, 2, 12) else y,
            .z = if (z >= std.math.pow(i32, 2, 25)) z - std.math.pow(i32, 2, 26) else z,
        };
    }

    pub fn toPacketPosition(self: BlockPos) u64 {
        return (@as(u64, @bitCast(u32, self.x & 0x3FFFFFF)) << 38) | (@as(u64, @bitCast(u32, self.z & 0x3FFFFFF)) << 12) | (@as(u64, @bitCast(u32, self.y)) & 0xFFF);
    }
};

test "BlockPos" {
    const pos = BlockPos{
        .x = -10,
        .y = 17,
        .z = -25,
    };
    const packet_pos = pos.toPacketPosition();
    const pos2 = BlockPos.fromPacketPosition(packet_pos);

    try std.testing.expectEqual(packet_pos, 0b1111111111111111111111011011111111111111111111100111000000010001);
    try std.testing.expectEqual(pos2, pos);
}
