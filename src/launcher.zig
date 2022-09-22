// the plan is if this ever gets to a releasable stage, we could release the game in
// source code form (copyright © all rights reserved header on every file) but
// it makes it trivial to mod
const std = @import("std");
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const render = @import("render.zig");
const c = sdl.c;
const log = std.log.scoped(.launcher);
const math = @import("math.zig");
const shared = @import("shared.zig");

const x = math.x;
const y = math.y;
const z = math.z;

// https://www.khronos.org/opengl/wiki/Buffer_Texture

var global_allocator: ?std.mem.Allocator = null;
pub fn allocator() std.mem.Allocator {
    return global_allocator.?;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if(gpa.deinit()) unreachable;
    ls.alloc = gpa.allocator();

    try sdl.sewrap(c.SDL_Init(c.SDL_INIT_VIDEO));

    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_DOUBLEBUFFER, 1 ));
    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_ACCELERATED_VISUAL, 1 ));
    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_RED_SIZE, 8 ));
    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_GREEN_SIZE, 8 ));
    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_BLUE_SIZE, 8 ));
    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_ALPHA_SIZE, 8 ));

    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_CONTEXT_MAJOR_VERSION, 3 ));
    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_CONTEXT_MINOR_VERSION, 2 ));
    try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE ));

    // - for mac trackpad gestures
    // if(c.SDL_SetHint( c.SDL_HINT_MOUSE_TOUCH_EVENTS, "1" ) == c.SDL_FALSE) {
    //     log.info("Emouse_touch_events 0?", .{});
    // }

    const window: *c.SDL_Window = c.SDL_CreateWindow(
        "Productgame",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        1920 / 2, 1080 / 2,
        c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
    ) orelse return sdl.sewrap(1);

    var prev_timestamp: f64 = 0;

    // TODO: display a loader while compiling the app


    const launcher_data: shared.LauncherData = .{
        .window = window,
        .reload = &extern_reload,
    };

    try reload();
    defer ls.lib.?.close();
    ls.data_ptr = ls.app.init(&launcher_data);
    defer ls.app.deinit(ls.data_ptr);

    while(true) {
        const curr_timestamp = @intToFloat(f64, std.time.milliTimestamp());
        defer prev_timestamp = curr_timestamp;

        while(sdl.pollEvent()) |event| {
            if(event.type == c.SDL_QUIT) {
                return;
            }
            ls.app.onEvent(ls.data_ptr, &event);
        }

        ls.app.onRender(ls.data_ptr);
    }
}

var ls: LauncherState = .{};

const LauncherState = struct {
    app: shared.App = undefined,
    lib: ?std.DynLib = null,
    data_ptr: usize = undefined,
    alloc: std.mem.Allocator = undefined,
    ver: usize = 0,
};

fn extern_reload() callconv(.C) void {
    reload() catch {
        @panic("todo passthrough error");
    };
}

fn reload() !void {
    if(ls.lib != null) {
        log.info("Reloading app", .{});
    }

    ls.ver += 1;
    const ourver = ls.ver;
    const verfmt = try std.fmt.allocPrint(ls.alloc, "-Dgamever={d}", .{ourver});
    defer ls.alloc.free(verfmt);

    var process = std.ChildProcess.init(&.{"zig", "build", "game", verfmt}, ls.alloc);
    const res = try process.spawnAndWait();
    if(res != .Exited or res.Exited != 0) return error.BuildFailed;

    const libext = switch (@import("builtin").os.tag) {
        .linux, .freebsd, .openbsd => "so",
        .windows => "dll",
        .macos, .tvos, .watchos, .ios => "dylib",
        else => @compileError("unsupported target"),
    };
    const libfile = try std.fmt.allocPrint(ls.alloc, "zig-out/lib/libproductgame-{d}.{s}", .{ourver, libext});
    defer ls.alloc.free(libfile);
    var lib = try std.DynLib.open(libfile);

    const get_app = lib.lookup(*const fn() callconv(.C) shared.App, "pg_get_app") orelse return error.BadDynlib;
    ls.app = get_app();

    if(ls.lib) |*prev_lib| {
        ls.app.initReplace(ls.data_ptr);
        // prev_lib.close();
        _ = prev_lib; // oh, we can't close it because we use some pointers to data in the previous lib I guess
        // strings would do that but I don't think I save any? not sure what it is then
        log.info("✓ Reloaded", .{});
    }else{
        // it is the caller's job to initialize app
    }
    ls.lib = lib;
}