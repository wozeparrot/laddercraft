const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const block = @import("../block/block.zig");

const CompactedDataArray = @import("compacted_data_array.zig").CompactedDataArray;

pub const ChunkSection = struct {
    data: CompactedDataArray,
    block_count: u16,

    pub fn init(alloc: *Allocator) !ChunkSection {
        return ChunkSection{
            .data = try CompactedDataArray.init(alloc, 15, 4096),
            .block_count = 0,
        };
    }

    pub fn deinit(self: *ChunkSection, alloc: *Allocator) void {
        self.data.deinit(alloc);
    }

    pub fn getBlock(self: *ChunkSection, x: u32, y: u32, z: u32) block.BlockState {
        return @intCast(block.BlockState, self.data.get(getIndex(x, y, z)));
    }

    pub fn setBlock(self: *ChunkSection, x: u32, y: u32, z: u32, block_state: block.BlockState) bool {
        const old_block = self.getBlock(x, y, z);
        if (old_block == 0 and block_state != 0) {
            self.block_count += 1;
        } else if (old_block != 0 and block_state == 0) {
            self.block_count -= 1;
        }
        self.data.set(getIndex(x, y, z), block_state);
        return old_block != block_state;
    }
};

fn getIndex(x: u32, y: u32, z: u32) usize {
    return @intCast(usize, (y << 8) | (z << 4) | x);
}
