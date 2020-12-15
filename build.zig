const std = @import("std");
const Pkg = @import("std").build.Pkg;
const Builder = @import("std").build.Builder;

const deps = struct {
    const pike = Pkg{
        .name = "pike",
        .path = "deps/pike/pike.zig",
    };
    const zap = Pkg{
        .name = "zap",
        .path = "deps/zap/src/zap.zig",
    };
    const zlm = Pkg{
        .name = "zlm",
        .path = "deps/zlm/zlm.zig",
    };

    const ladder_core = Pkg{
        .name = "ladder_core",
        .path = "core/lib.zig",
        .dependencies = &[_]Pkg{
            pike, zlm,
        },
    };
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ladder", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addPackage(deps.pike);
    exe.addPackage(deps.zap);
    exe.addPackage(deps.zlm);

    exe.addPackage(deps.ladder_core);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
