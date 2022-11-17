const nbt = @import("../nbt/nbt.zig");

pub const MAX_PACKET_SIZE = 2097151;

pub const BASIC_REGISTRY_CODEC = nbt.Tag{
    .compound = .{
        .name = "",
        .payload = &[_]nbt.Tag{
            .{
                .compound = .{
                    .name = "minecraft:chat_type",
                    .payload = &[_]nbt.Tag{
                        .{
                            .string = .{
                                .name = "type",
                                .payload = "minecraft:chat_type",
                            },
                        },
                        .{
                            .list = .{
                                .name = "value",
                                .payload = &[_]nbt.Tag{},
                            },
                        },
                    },
                },
            },
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
                                                                    .payload = "#minecraft:infiniburn_overworld",
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
                                                            .{
                                                                .int = .{
                                                                    .name = "monster_spawn_block_light_limit",
                                                                    .payload = 0,
                                                                },
                                                            },
                                                            .{
                                                                .compound = .{
                                                                    .name = "monster_spawn_light_level",
                                                                    .payload = &[_]nbt.Tag{
                                                                        .{
                                                                            .string = .{
                                                                                .name = "type",
                                                                                .payload = "minecraft:uniform",
                                                                            },
                                                                        },
                                                                        .{
                                                                            .compound = .{
                                                                                .name = "value",
                                                                                .payload = &[_]nbt.Tag{
                                                                                    .{
                                                                                        .int = .{
                                                                                            .name = "min_inclusive",
                                                                                            .payload = 0,
                                                                                        },
                                                                                    },
                                                                                    .{
                                                                                        .int = .{
                                                                                            .name = "max_inclusive",
                                                                                            .payload = 7,
                                                                                        },
                                                                                    },
                                                                                },
                                                                            },
                                                                        },
                                                                    },
                                                                },
                                                            },
                                                            .{
                                                                .int = .{
                                                                    .name = "height",
                                                                    .payload = 256,
                                                                },
                                                            },
                                                            .{
                                                                .int = .{
                                                                    .name = "min_y",
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
                                                                    .payload = "none",
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "depth",
                                                                    .payload = 0.0,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "temperature",
                                                                    .payload = 0.5,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "scale",
                                                                    .payload = 0.0,
                                                                },
                                                            },
                                                            .{
                                                                .float = .{
                                                                    .name = "downfall",
                                                                    .payload = 0.0,
                                                                },
                                                            },
                                                            .{
                                                                .string = .{
                                                                    .name = "category",
                                                                    .payload = "plains",
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
    },
};
