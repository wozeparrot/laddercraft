const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const zlm = @import("zlm").specializeOn(f64);

pub fn readVarInt(reader: anytype) !i32 {
    var result: u32 = 0;

    var num_read: u32 = 0;
    var read = try reader.readByte();

    while ((read & 0b10000000) != 0) {
        var value: u32 = (read & 0b01111111);
        result |= (value << @intCast(u5, 7 * num_read));
        
        num_read += 1;
        read = try reader.readByte();
    }
    var value: u32 = (read & 0b01111111);
    result |= (value << @intCast(u5, 7 * num_read));

    return @bitCast(i32, result);
}

pub fn readByteArray(alloc: *Allocator, reader: anytype, length: i32) ![]u8 {
    var buf = try alloc.alloc(u8, @intCast(usize, length));
    var strm = std.io.fixedBufferStream(buf);
    var wr = strm.writer();

    var i: usize = 0;
    while (i < length) : (i += 1) {
        try wr.writeByte(try reader.readByte());
    }

    return buf;
}

pub fn writeVarInt(writer: anytype, value: i32) !void {
    var tmp_value: u32 = @bitCast(u32, value);
    var tmp: u8 = @truncate(u8, tmp_value) & 0b01111111;
    tmp_value >>= 7;
    if (tmp_value != 0) {
        tmp |= 0b10000000;
    }
    try writer.writeByte(tmp);
    while (tmp_value != 0) {
        tmp = @truncate(u8, tmp_value) & 0b01111111;
        tmp_value >>= 7;
        if (tmp_value != 0) {
            tmp |= 0b10000000;
        }
        try writer.writeByte(tmp);
    }
}

pub fn writeByteArray(writer: anytype, data: []const u8) !void {
    try writeVarInt(writer, @intCast(i32, data.len));
    try writer.writeAll(data);
}

pub fn writeJSONStruct(alloc: *Allocator, writer: anytype, value: anytype) !void {
    var array_list = std.ArrayList(u8).init(alloc);
    defer array_list.deinit();

    try std.json.stringify(value, .{}, array_list.outStream());

    try writeByteArray(writer, array_list.toOwnedSlice());
}

pub fn toPacketPosition(vec: zlm.Vec3) u64 {
    return ((@floatToInt(u64, vec.x) & 0x3FFFFFF) << 38) | ((@floatToInt(u64, vec.z) & 0x3FFFFFF) << 12) | (@floatToInt(u64, vec.y) & 0xFFF);
}