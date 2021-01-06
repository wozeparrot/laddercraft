const nbt = @import("../nbt/nbt.zig");

pub const Inventory = struct {
    slots: [46]?Slot = [_]?Slot{null} ** 46,
};

pub const Slot = struct {
    id: i32 = -1,
    count: u8 = 0,
    nbt: nbt.Tag = nbt.Tag{ .end = {} },
};