const std = @import("std");
const json = std.json;

pub const Text = struct {
    text: []const u8,

    bold: bool = false,
    italic: bool = false,
    underlined: bool = false,
    strikethrough: bool = false,
    obfuscated: bool = false,

    color: Color = .white,
};

pub const Color = enum {
    black,
    dark_blue,
    dark_green,
    dark_aqua,
    dark_red,
    dark_purple,
    gold,
    gray,
    dark_gray,
    blue,
    green,
    aqua,
    red,
    light_purple,
    yellow,
    white,

    pub fn jsonStringify(self: Color, options: json.StringifyOptions, out_stream: anytype) !void {
        _ = options;
        try std.fmt.format(out_stream, "\"{s}\"", .{@tagName(self)});
    }
};
