const std = @import("std");
const Pkg = @import("std").build.Pkg;
const Builder = @import("std").build.Builder;

const zlm_pkg = Pkg{
    .name = "zlm",
    .source = .{ .path = "deps/zlm/zlm.zig" },
};

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ladder", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.use_stage1 = true;

    exe.addPackage(zlm_pkg);

    exe.addPackage(Pkg{
        .name = "ladder_core",
        .source = .{ .path = "core/lib.zig" },
        .dependencies = &[_]Pkg{zlm_pkg},
    });

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
