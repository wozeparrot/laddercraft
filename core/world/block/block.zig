pub usingnamespace @import("block_state.zig");
pub usingnamespace @import("block_entity.zig");

const zlm = @import("zlm").specializeOn(f64);

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

    pub fn toPacketPosition(self: BlockPos) u64 {
        return ((self.x & 0x3FFFFFF) << 38) | ((self.z & 0x3FFFFFF) << 12) | (self.y & 0xFFF);
    }
};