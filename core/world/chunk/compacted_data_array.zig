const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const block = @import("../block/block.zig");

// Compacted Chunk Data Store
pub const CompactedDataArray = struct {
    data: []u64,

    elements: usize,
    element_bits: u6,
    elements_per_long: u64,
    mask: u64,

    pub fn init(alloc: *Allocator, element_bits: u6, elements: usize) !CompactedDataArray {
        const elements_per_long = 64 / @intCast(u64, element_bits);

        const data = try alloc.alloc(u64, (elements + @intCast(usize, elements_per_long) - 1) / @intCast(usize, elements_per_long));
        std.mem.set(u64, data, 0);

        return CompactedDataArray{
            .data = data,

            .elements = elements,
            .element_bits = element_bits,
            .elements_per_long = elements_per_long,
            .mask = (@as(u64, 1) << element_bits) - 1,
        };
    }

    pub fn deinit(self: *CompactedDataArray, alloc: *Allocator) void {
        alloc.free(self.data);
    }

    pub fn set(self: *CompactedDataArray, index: usize, value: u32) void {
        const pos = index / @intCast(usize, self.elements_per_long);
        const offset = (index - pos * self.elements_per_long) * self.element_bits;

        const mask = ~(self.mask << @intCast(u6, offset));
        self.data[pos] = (self.data[pos] & mask) | (@as(u64, value) << @intCast(u6, offset));
    }

    pub fn get(self: *CompactedDataArray, index: usize) u32 {
        const pos = index / @intCast(usize, self.elements_per_long);
        const offset = (index - pos * self.elements_per_long) * self.element_bits;

        return @intCast(u32, (self.data[pos] >> @intCast(u6, offset)) & self.mask);
    }
};

test "CompactedDataArray" {
    var alloc = std.testing.allocator;
    var data = try CompactedDataArray.init(alloc, 5, 24);
    defer data.deinit(alloc);

    data.set(0, 1);
    data.set(1, 2);
    data.set(2, 2);
    data.set(3, 3);
    data.set(4, 4);
    data.set(5, 4);
    data.set(6, 5);
    data.set(7, 6);
    data.set(8, 6);
    data.set(9, 4);
    data.set(10, 8);
    data.set(11, 0);
    data.set(12, 7);
    data.set(13, 4);
    data.set(14, 3);
    data.set(15, 13);
    data.set(16, 15);
    data.set(17, 16);
    data.set(18, 9);
    data.set(19, 14);
    data.set(20, 10);
    data.set(21, 12);
    data.set(22, 0);
    data.set(23, 2);

    std.testing.expectEqual(data.data[0], 0x0020863148418841);
    std.testing.expectEqual(data.data[1], 0x01018A7260F68C87);
}

// Compacted Data Array but with a Palette
pub const PalettedDataArray = struct {

};