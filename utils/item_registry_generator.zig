// Generates a block registry from minecraft's data generator

const std = @import("std");

// current parser state
const State = enum {
    item,
    none,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var output = std.ArrayList(u8).init(alloc);
    defer output.deinit();
    const writer = output.writer();
    try writer.writeAll(
        \\
        \\pub const Item = struct {
        \\    protocol_id: u16 = 0,
        \\};
        \\
        \\
    );

    // item to block mapping
    var i2b_mapping = std.ArrayList(u8).init(alloc);
    defer i2b_mapping.deinit();
    const i2bm_writer = i2b_mapping.writer();
    try i2bm_writer.writeAll(
        \\pub const ItemToBlock = &[_]u16{
        \\    
    );

    // embed json data file
    const json = @embedFile("data/items.json");
    var stream = std.json.TokenStream.init(json);
    std.debug.assert((try stream.next()).? == .ObjectBegin);

    var state: State = .none;
    var current_item_id: u16 = 0;

    const blocks = comptime std.meta.declarations(@import("blocks.zig"));
    const block_names = comptime blk: {
        var names = [_][]const u8{""} ** blocks.len;
        for (blocks) |decl, i| {
            names[i] = decl.name;
        }
        break :blk names;
    };

    while (try stream.next()) |tok| {
        switch (tok) {
            .String => |t| {
                switch (state) {
                    .none => {
                        try writer.writeAll("pub const @\"");
                        try writer.writeAll(t.slice(json, stream.i - 1));
                        try writer.writeAll("\" = Item{\n");

                        if (indexOfSlice([]const u8, block_names[0..], t.slice(json, stream.i - 1))) |pos| {
                            try i2bm_writer.print("{}, ", .{pos - 4});
                        } else {
                            try i2bm_writer.writeAll("0, ");
                        }

                        state = .item;
                    },
                    .item => {
                        if (std.mem.eql(u8, t.slice(json, stream.i - 1), "protocol_id")) {
                            try writer.writeAll(".protocol_id = ");
                        } else std.debug.panic("broken json: {s} at {}", .{ t.slice(json, stream.i - 1), stream.i });
                    },
                }
            },
            .Number => |t| {
                switch (state) {
                    .item => {
                        try writer.writeAll(t.slice(json, stream.i - 1));
                        try writer.writeAll(",\n");
                    },
                    else => {},
                }
            },
            .ObjectEnd => {
                switch (state) {
                    .item => {
                        try writer.writeAll("};\n");
                        state = .none;
                        current_item_id += 1;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    try i2bm_writer.writeAll("\n};\n");

    var file = try std.fs.cwd().createFile("items.zig", .{});
    defer file.close();
    try file.writeAll(i2b_mapping.toOwnedSlice());
    try file.writeAll(output.toOwnedSlice());
}

fn indexOfSlice(comptime T: type, slice: []const T, value: T) ?usize {
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        if (std.mem.eql(u8, slice[i], value)) return i;
    }
    return null;
}
