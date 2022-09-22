const std = @import("std");

fn libcfg(b: *std.build.Builder, exe: *std.build.LibExeObjStep, target: std.zig.CrossTarget, mode: std.builtin.Mode) void {
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.linkLibC();
    if(target.isDarwin()) {
        exe.linkFramework("Cocoa");
        exe.linkFramework("OpenGL");
        exe.linkSystemLibrary("SDL2");
        exe.addCSourceFile("src/inertialscroll.m", &[_][]const u8{""});
    }else if(target.isLinux()) {
        exe.linkSystemLibrary("SDL2");
        exe.linkSystemLibrary("GL");
    }else{
        @panic("unsupported target");
    }

    _ = b;
}

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const verstr = b.option([]const u8, "gamever", "for the launcher to use") orelse "nover";

    const exe = b.addSharedLibrary(b.fmt("productgame-{s}", .{verstr}), "src/main.zig", .unversioned);
    libcfg(b, exe, target, mode);

    const exe_install = b.addInstallArtifact(exe);
    const game_step = b.step("game", "Build the game");
    game_step.dependOn(&exe_install.step);

    const launcher = b.addExecutable("productlauncher", "src/launcher.zig");
    libcfg(b, launcher, target, mode);

    const launcher_install = b.addInstallArtifact(launcher);
    b.getInstallStep().dependOn(&launcher_install.step);

    const run_cmd = launcher.run();
    run_cmd.step.dependOn(&launcher_install.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the launcher");
    run_step.dependOn(&run_cmd.step);
}
