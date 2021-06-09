pub const ConnectionState = enum(u8) {
    handshake = 0,
    status = 1,
    login = 2,
    play = 3,
};
