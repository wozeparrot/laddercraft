const nbt = @import("../nbt/nbt.zig");

pub const MAX_PACKET_SIZE = 2097151;

pub const BASIC_DIMENSION_CODEC = nbt.Tag{
    .compound = .{
        .name = "",
        .payload = &[_]nbt.Tag{
            .{
                .compound = .{
                    .name = "minecraft:dimension_type",
                    .payload = &[_]nbt.Tag{
                        .{
                            .string = .{
                                .name = "type",
                                .payload = "minecraft:dimension_type",
                            },
                        },
                        .{
                            .list = .{
                                .name = "value",
                                .payload = &[_]nbt.Tag{
                                    .{
                                        .compound = .{
                                            .name = "",
                                            .payload = &[_]nbt.Tag{
                                                .{
                                                    .string = .{
                                                        .name = "name",
                                                        .payload = "minecraft:overworld",
                                                    },
                                                },
                                                .{
                                                    .byte = .{
                                                        .name = "id",
                                                        .payload = 0,
                                                    },
                                                },
                                                .{
                                                    .compound = .{
                                                        .name = "element",
                                                        .payload = &[_]nbt.Tag{
                                                            .{
                                                                .byte = .{
                                                                    .name = "piglin_safe",
                                                                    .payload = 0,
                                                                },
                                                            },
                                                            .{
                                                                .byte = .{
                                                                    .name = "natural",
                                                                    .payload = 1,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "ambient_light",
                                                                    .payload = 0,
                                                                },
                                                            },
                                                            .{
                                                                .string = .{
                                                                    .name = "infiniburn",
                                                                    .payload = "minecraft:infiniburn_overworld",
                                                                },
                                                            },
                                                            .{
                                                                .byte = .{
                                                                    .name = "respawn_anchor_works",
                                                                    .payload = 0,
                                                                },
                                                            },
                                                            .{
                                                                .byte = .{
                                                                    .name = "has_skylight",
                                                                    .payload = 1,
                                                                },
                                                            },
                                                            .{
                                                                .byte = .{
                                                                    .name = "bed_works",
                                                                    .payload = 1,
                                                                },
                                                            },
                                                            .{
                                                                .string = .{
                                                                    .name = "effects",
                                                                    .payload = "minecraft:overworld",
                                                                },
                                                            },
                                                            .{
                                                                .byte = .{
                                                                    .name = "has_raids",
                                                                    .payload = 1,
                                                                },
                                                            },
                                                            .{
                                                                .int = .{
                                                                    .name = "logical_height",
                                                                    .payload = 256,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "coordinate_scale",
                                                                    .payload = 1.0,
                                                                },
                                                            },
                                                            .{
                                                                .byte = .{
                                                                    .name = "ultrawarm",
                                                                    .payload = 0,
                                                                },
                                                            },
                                                            .{
                                                                .byte = .{
                                                                    .name = "has_ceiling",
                                                                    .payload = 0,
                                                                },
                                                            },
                                                        },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
            .{
                .compound = .{
                    .name = "minecraft:worldgen/biome",
                    .payload = &[_]nbt.Tag{
                        .{
                            .string = .{
                                .name = "type",
                                .payload = "minecraft:worldgen/biome",
                            },
                        },
                        .{
                            .list = .{
                                .name = "value",
                                .payload = &[_]nbt.Tag{
                                    .{
                                        .compound = .{
                                            .name = "",
                                            .payload = &[_]nbt.Tag{
                                                .{
                                                    .string = .{
                                                        .name = "name",
                                                        .payload = "minecraft:plains",
                                                    },
                                                },
                                                .{
                                                    .int = .{
                                                        .name = "id",
                                                        .payload = 0,
                                                    },
                                                },
                                                .{
                                                    .compound = .{
                                                        .name = "element",
                                                        .payload = &[_]nbt.Tag{
                                                            .{
                                                                .string = .{
                                                                    .name = "precipitation",
                                                                    .payload = "rain",
                                                                },
                                                            },
                                                            .{
                                                                .compound = .{
                                                                    .name = "effects",
                                                                    .payload = &[_]nbt.Tag{
                                                                        .{
                                                                            .int = .{
                                                                                .name = "sky_color",
                                                                                .payload = 7907327,
                                                                            },
                                                                        },
                                                                        .{
                                                                            .int = .{
                                                                                .name = "water_fog_color",
                                                                                .payload = 329011,
                                                                            },
                                                                        },
                                                                        .{
                                                                            .int = .{
                                                                                .name = "fog_color",
                                                                                .payload = 12638463,
                                                                            },
                                                                        },
                                                                        .{
                                                                            .int = .{
                                                                                .name = "water_color",
                                                                                .payload = 4159204,
                                                                            },
                                                                        },
                                                                        .{
                                                                            .compound = .{
                                                                                .name = "mood_sound",
                                                                                .payload = &[_]nbt.Tag{
                                                                                    .{
                                                                                        .int = .{
                                                                                            .name = "tick_delay",
                                                                                            .payload = 6000,
                                                                                        },
                                                                                    },
                                                                                    .{
                                                                                        .double = .{
                                                                                            .name = "offset",
                                                                                            .payload = 2.0,
                                                                                        },
                                                                                    },
                                                                                    .{
                                                                                        .string = .{
                                                                                            .name = "sound",
                                                                                            .payload = "minecraft:ambient.cave",
                                                                                        },
                                                                                    },
                                                                                    .{
                                                                                        .int = .{
                                                                                            .name = "block_search_extent",
                                                                                            .payload = 8,
                                                                                        },
                                                                                    },
                                                                                },
                                                                            },
                                                                        },
                                                                    },
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "depth",
                                                                    .payload = 0.125,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "temperature",
                                                                    .payload = 0.8,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "scale",
                                                                    .payload = 0.05,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "downfall",
                                                                    .payload = 0.4,
                                                                },
                                                            },
                                                            .{
                                                                .string = .{
                                                                    .name = "category",
                                                                    .payload = "plains",
                                                                },
                                                            },
                                                        },
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
};

pub const BASIC_DIMENSION = nbt.Tag{
    .compound = .{
        .name = "",
        .payload = &[_]nbt.Tag{
            .{
                .byte = .{
                    .name = "piglin_safe",
                    .payload = 0,
                },
            },
            .{
                .byte = .{
                    .name = "natural",
                    .payload = 1,
                },
            },
            .{
                .float = .{
                    .name = "ambient_light",
                    .payload = 0,
                },
            },
            .{
                .string = .{
                    .name = "infiniburn",
                    .payload = "minecraft:infiniburn_overworld",
                },
            },
            .{
                .byte = .{
                    .name = "respawn_anchor_works",
                    .payload = 0,
                },
            },
            .{
                .byte = .{
                    .name = "has_skylight",
                    .payload = 1,
                },
            },
            .{
                .byte = .{
                    .name = "bed_works",
                    .payload = 1,
                },
            },
            .{
                .string = .{
                    .name = "effects",
                    .payload = "minecraft:overworld",
                },
            },
            .{
                .byte = .{
                    .name = "has_raids",
                    .payload = 1,
                },
            },
            .{
                .int = .{
                    .name = "logical_height",
                    .payload = 256,
                },
            },
            .{
                .float = .{
                    .name = "coordinate_scale",
                    .payload = 1.0,
                },
            },
            .{
                .byte = .{
                    .name = "ultrawarm",
                    .payload = 0,
                },
            },
            .{
                .byte = .{
                    .name = "has_ceiling",
                    .payload = 0,
                },
            },
        },
    },
};
