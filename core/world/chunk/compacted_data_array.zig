const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

pub const CompactedDataArray = struct {
    pack: std.PackedIntSliceEndian(u1, .Big),
    element_bits: u4,

    data: []u8,

    pub fn init(alloc: *Allocator, element_bits: u4, size: usize) !CompactedDataArray {
        const data = try alloc.alloc(u8, element_bits * size);
        const pack = std.PackedIntSliceEndian(u1, .Big).init(data, element_bits * size);

        return CompactedDataArray{
            .pack = pack,
            .element_bits = element_bits,

            .data = data,
        };
    }

    pub fn deinit(self: *CompactedDataArray, alloc: *Allocator) void {
        alloc.free(self.data);
    }
};