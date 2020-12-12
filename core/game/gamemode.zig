pub const Gamemode = struct {
    mode: enum (u8) {
        survival,
        creative,
        adventure,
        spectator,
    },
    hardcore: bool
};