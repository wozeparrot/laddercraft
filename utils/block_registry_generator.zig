// Generates a block registry from minecraft's data generator

const std = @import("std");

// current parser state
const State = enum {
    block,
    properties,
    property,
    in_property,
    states,
    state,
    s_properties,
    s_property,
    in_s_property,
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
        \\pub const Block = struct {
        \\    const Property = struct {
        \\        name: []const u8,
        \\        states: []const []const u8,
        \\    };
        \\
        \\    const State = struct {
        \\          id: u16,
        \\          default: bool = false,
        \\          properties: []const Property = &[_]Property{},
        \\    };
        \\
        \\    properties: []const Property = &[_]Property{},
        \\    states: []const State,
        \\};
        \\
        \\
    );

    // state to block mapping
    var s2b_mapping = std.ArrayList(u8).init(alloc);
    defer s2b_mapping.deinit();
    const s2bm_writer = s2b_mapping.writer();
    try s2bm_writer.writeAll(
        \\pub const StateToBlock = &[_]u16{
        \\    
    );

    // block to default state mapping
    var b2ds_mapping = std.ArrayList(u8).init(alloc);
    defer b2ds_mapping.deinit();
    const b2dsm_writer = b2ds_mapping.writer();
    try b2dsm_writer.writeAll(
        \\pub const BlockToDefaultState = &[_]u16{
        \\    
    );

    // block to base state mapping
    var b2bs_mapping = std.ArrayList(u8).init(alloc);
    defer b2bs_mapping.deinit();
    const b2bsm_writer = b2bs_mapping.writer();
    try b2bsm_writer.writeAll(
        \\pub const BlockToBaseState = &[_]u16{
        \\    
    );

    // embed json data file
    const json = @embedFile("data/blocks.json");
    var stream = std.json.TokenStream.init(json);
    std.debug.assert((try stream.next()).? == .ObjectBegin);

    var state: State = .none;
    var current_block_id: u16 = 0;
    var current_state_id: u16 = 0;

    while (try stream.next()) |tok| {
        switch (tok) {
            .String => |t| {
                switch (state) {
                    .none => {
                        try writer.writeAll("pub const @\"");
                        try writer.writeAll(t.slice(json, stream.i - 1));
                        try writer.writeAll("\" = Block{\n");

                        try b2bsm_writer.print("{}, ", .{current_state_id});

                        state = .block;
                    },
                    .block => {
                        if (std.mem.eql(u8, t.slice(json, stream.i - 1), "states")) {
                            try writer.writeAll(".states = &[_]Block.State{\n");
                            state = .states;
                        } else if (std.mem.eql(u8, t.slice(json, stream.i - 1), "properties")) {
                            try writer.writeAll(".properties = &[_]Block.Property{\n");
                            state = .properties;
                        } else std.debug.panic("broken json: {s} at {}", .{ t.slice(json, stream.i - 1), stream.i });
                    },
                    .properties => {
                        try writer.writeAll(".{\n");
                        try writer.writeAll(".name = \"");
                        try writer.writeAll(t.slice(json, stream.i - 1));
                        try writer.writeAll("\",\n.states = &[_][]const u8{\n");
                        state = .property;
                    },
                    .property => {
                        try writer.writeByte('"');
                        try writer.writeAll(t.slice(json, stream.i - 1));
                        try writer.writeAll("\",\n");
                    },
                    .state => {
                        const slice = t.slice(json, stream.i - 1);
                        if (std.mem.eql(u8, slice, "id")) {
                            try writer.writeAll(".id = ");
                        } else if (std.mem.eql(u8, slice, "default")) {
                            try writer.writeAll(".default = true,\n");

                            try b2dsm_writer.print("{}, ", .{current_state_id - 1});
                        } else if (std.mem.eql(u8, slice, "properties")) {
                            try writer.writeAll(",\n.properties = &[_]Block.Property{\n");
                            state = .s_properties;
                        }
                    },
                    .s_properties => {
                        try writer.writeAll(".{\n");
                        try writer.writeAll(".name = \"");
                        try writer.writeAll(t.slice(json, stream.i - 1));
                        try writer.writeAll("\",\n.states = &[_][]const u8{\n");
                        state = .s_property;
                    },
                    .s_property => {
                        try writer.writeByte('"');
                        try writer.writeAll(t.slice(json, stream.i - 1));
                        try writer.writeAll("\",\n},},\n");
                        state = .s_properties;
                    },
                    else => {},
                }
            },
            .Number => |t| {
                switch (state) {
                    .state => {
                        try writer.writeAll(t.slice(json, stream.i - 1));

                        try s2bm_writer.print("{}, ", .{current_block_id});

                        current_state_id += 1;
                        // current_state_id = try std.fmt.parseUnsigned(u16, t.slice(json, stream.i - 1), 10);
                    },
                    else => {},
                }
            },
            .ObjectBegin => {
                switch (state) {
                    .states => {
                        try writer.writeAll(".{\n");
                        state = .state;
                    },
                    else => {},
                }
            },
            .ArrayEnd => {
                switch (state) {
                    .states => {
                        try writer.writeAll("},\n");
                        state = .block;
                    },
                    .property => {
                        try writer.writeAll("},\n},\n");
                        state = .properties;
                    },
                    .s_property => {
                        try writer.writeAll("},\n},\n");
                        state = .s_properties;
                    },
                    else => {},
                }
            },
            .ObjectEnd => {
                switch (state) {
                    .block => {
                        try writer.writeAll("};\n");
                        state = .none;
                        current_block_id += 1;
                    },
                    .properties => {
                        try writer.writeAll("},\n");
                        state = .block;
                    },
                    .state => {
                        try writer.writeAll("},\n");
                        state = .states;
                    },
                    .s_properties => {
                        try writer.writeAll("},\n");
                        state = .state;
                    },
                    else => {},
                }
            },
            else => {},
        }
    }

    try s2bm_writer.writeAll("\n};\n");
    try b2dsm_writer.writeAll("\n};\n");
    try b2bsm_writer.writeAll("\n};\n");

    var file = try std.fs.cwd().createFile("blocks.zig", .{});
    defer file.close();
    try file.writeAll(s2b_mapping.toOwnedSlice());
    try file.writeAll(b2ds_mapping.toOwnedSlice());
    try file.writeAll(b2bs_mapping.toOwnedSlice());
    try file.writeAll(output.toOwnedSlice());
}
