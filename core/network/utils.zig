const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

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
    var array_list = std.ArrayList(u8).init(alloc);
    defer array_list.deinit();
    
    var i: usize = 0;
    while (i < length) : (i += 1) {
        try array_list.append(try reader.readByte());
    }

    return array_list.toOwnedSlice();
}

pub fn writeVarInt(writer: anytype, value: i32) !void {
    var tmp_value: u32 = @bitCast(u32, value);
    while (tmp_value != 0) {
        var tmp: u8 = @truncate(u8, tmp_value) & 0b01111111;
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