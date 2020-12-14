pub const Tag = union(enum(u8)) {
    end: void,
    byte: struct { name: []const u8, payload: i8 },
    short: struct { name: []const u8, payload: i16 },
    int: struct { name: []const u8, payload: i32 },
    long: struct { name: []const u8, payload: i64 },
    float: struct { name: []const u8, payload: f32 },
    double: struct { name: []const u8, payload: f64 },
    byte_array: struct { name: []const u8, payload: []const u8 },
    string: struct { name: []const u8, payload: []const u8 },
    list: struct { name: []const u8, payload: []const Tag },
    compound: struct { name: []const u8, payload: []const Tag },
    int_array: struct { name: []const u8, payload: []i32 },
    long_array: struct { name: []const u8, payload: []i64 },
};

pub fn writeTag(writer: anytype, tag: Tag, payload_only: bool) anyerror!void {
    switch (tag) {
        .end => try writer.writeByte(0),
        .byte => {
            if (!payload_only) {
                try writer.writeByte(1);
                try writer.writeIntBig(u16, @intCast(u16, tag.byte.name.len));
                try writer.writeAll(tag.byte.name);
            }
            try writer.writeByte(@bitCast(u8, tag.byte.payload));
        },
        .short => {
            if (!payload_only) {
                try writer.writeByte(2);
                try writer.writeIntBig(u16, @intCast(u16, tag.short.name.len));
                try writer.writeAll(tag.short.name);
            }
            try writer.writeIntBig(i16, tag.short.payload);
        },
        .int => {
            if (!payload_only) {
                try writer.writeByte(3);
                try writer.writeIntBig(u16, @intCast(u16, tag.int.name.len));
                try writer.writeAll(tag.int.name);
            }
            try writer.writeIntBig(i32, tag.int.payload);
        },
        .long => {
            if (!payload_only) {
                try writer.writeByte(4);
                try writer.writeIntBig(u16, @intCast(u16, tag.long.name.len));
                try writer.writeAll(tag.long.name);
            }
            try writer.writeIntBig(i64, tag.long.payload);
        },
        .float => {
            if (!payload_only) {
                try writer.writeByte(5);
                try writer.writeIntBig(u16, @intCast(u16, tag.float.name.len));
                try writer.writeAll(tag.float.name);
            }
            try writer.writeIntBig(u32, @bitCast(u32, tag.float.payload));
        },
        .double => {
            if (!payload_only) {
                try writer.writeByte(6);
                try writer.writeIntBig(u16, @intCast(u16, tag.double.name.len));
                try writer.writeAll(tag.double.name);
            }
            try writer.writeIntBig(u64, @bitCast(u64, tag.double.payload));
        },
        .byte_array => {
            if (!payload_only) {
                try writer.writeByte(7);
                try writer.writeIntBig(u16, @intCast(u16, tag.byte_array.name.len));
                try writer.writeAll(tag.byte_array.name);
            }
            try writer.writeIntBig(i32, @intCast(i32, tag.byte_array.payload.len));
            try writer.writeAll(tag.byte_array.payload);
        },
        .string => {
            if (!payload_only) {
                try writer.writeByte(8);
                try writer.writeIntBig(u16, @intCast(u16, tag.string.name.len));
                try writer.writeAll(tag.string.name);
            }
            try writer.writeIntBig(u16, @intCast(u16, tag.string.payload.len));
            try writer.writeAll(tag.string.payload);
        },
        .list => {
            if (!payload_only) {
                try writer.writeByte(9);
                try writer.writeIntBig(u16, @intCast(u16, tag.list.name.len));
                try writer.writeAll(tag.list.name);
            }
            if (tag.list.payload.len <= 0) {
                try writer.writeByte(0);
                try writer.writeIntBig(i32, @intCast(i32, tag.list.payload.len));
            } else {
                try writer.writeByte(@enumToInt(tag.list.payload[0]));
                try writer.writeIntBig(i32, @intCast(i32, tag.list.payload.len));
                for (tag.list.payload) |t| try writeTag(writer, t, true);
            }
        },
        .compound => {
            if (!payload_only) {
                try writer.writeByte(10);
                try writer.writeIntBig(u16, @intCast(u16, tag.compound.name.len));
                try writer.writeAll(tag.compound.name);
            }
            for (tag.compound.payload) |t| try writeTag(writer, t, false);
            try writer.writeByte(0);
        },
        .int_array => {
            if (!payload_only) {
                try writer.writeByte(11);
                try writer.writeIntBig(u16, @intCast(u16, tag.int_array.name.len));
                try writer.writeAll(tag.int_array.name);
            }
            try writer.writeIntBig(i32, @intCast(i32, tag.int_array.payload.len));
            for (tag.int_array.payload) |int| try writer.writeIntBig(i32, int);
        },
        .long_array => {
            if (!payload_only) {
                try writer.writeByte(12);
                try writer.writeIntBig(u16, @intCast(u16, tag.long_array.name.len));
                try writer.writeAll(tag.long_array.name);
            }
            try writer.writeIntBig(i32, @intCast(i32, tag.long_array.payload.len));
            for (tag.long_array.payload) |long| try writer.writeIntBig(i64, long);
        },
    }
}
