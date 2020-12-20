const std = @import("std");
const rand = std.rand;

// modified from https://github.com/ziglang/zig/blob/c177a7ca34d2a141fdbd9b6b829498952c4321cc/lib/std/uuid.zig
pub const UUID = struct {
    version: enum {
        v3, v4
    },
    uuid: u128,

    /// Creates a new v3 UUID
    pub fn newv3(input: []const u8) UUID {
        var out: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(input, &out, .{});

        var uuid: u128 = 0;
        for (out) |byte, i| {
            uuid |= @as(u128, @as(u8, @bitReverse(u4, @truncate(u4, byte))) | (@as(u8, @bitReverse(u4, @truncate(u4, byte >> 4))) << 4)) << (15 - @intCast(u7, i)) * 8;
        }
        uuid = @bitReverse(u128, uuid);

        const flip: u128 = 0b1111 << 48;
        return UUID{ .version = .v3, .uuid = ((uuid & ~flip) | (0x3 << 48)) };
    }

    /// Creates a new v4 UUID
    pub fn newv4(r: *rand.Random) UUID {
        const flip: u128 = 0b1111 << 48;
        return UUID{ .version = .v4, .uuid = ((r.int(u128) & ~flip) | (0x4 << 48)) };
    }

    /// Creates a string from the ID.
    pub fn format(self: UUID, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        var buf = [_]u8{0} ** 36;

        var chars = "0123456789abcdef";

        //Pre-set known values
        buf[8] = '-';
        buf[13] = '-';
        switch (self.version) {
            .v3 => buf[14] = '3',
            .v4 => buf[14] = '4',
        }
        buf[18] = '-';
        buf[23] = '-';

        //Generate the string
        var i: usize = 0;
        var shift: u8 = 0;
        while (i < 36) : (i += 1) {
            //Skip pre-set values
            if (i != 8 and i != 13 and i != 18 and i != 23) {
                const selector = @truncate(u4, self.uuid >> @truncate(u7, shift));
                shift += 4;

                buf[i] = chars[@intCast(usize, selector)];
            }
        }

        try writer.writeAll(buf[0..]);
    }
};

test "UUID" {
    const v3 = UUID.newv3("OfflinePlayer:wozeparrot");
    std.testing.expectEqual(v3.uuid, 216409540031814485994237107467455717738);
}
