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
    const launcher_alloc = gpa.allocator();

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

    var process = std.ChildProcess.init(&.{"zig", "build", "game"}, launcher_alloc);
    const res = try process.spawnAndWait();
    if(res != .Exited or res.Exited != 0) return error.BuildFailed;

    const libname = switch (@import("builtin").os.tag) {
        .linux, .freebsd, .openbsd => "zig-out/lib/libproductgame.so",
        .windows => "zig-out/lib/libproductgame.dll",
        .macos, .tvos, .watchos, .ios => "zig-out/lib/libproductgame.dylib",
        else => @compileError("unsupported target"),
    };
    var lib = try std.DynLib.open(libname);
    defer lib.close();
    // when loading a new version:
    // 1. open the new dynlib
    // 2. call a 'onCreate' function with its data pointer so it can set its internal state
    // 3. close the old dynlib
    const get_app = lib.lookup(*const fn() callconv(.C) shared.App, "pg_get_app") orelse return error.BadDynlib;
    const app = get_app();

    const launcher_data: shared.LauncherData = .{
        .window = window,
    };
    const app_data_ptr = app.init(&launcher_data);
    defer app.deinit(app_data_ptr);

    while(true) {
        const curr_timestamp = @intToFloat(f64, std.time.milliTimestamp());
        defer prev_timestamp = curr_timestamp;

        while(sdl.pollEvent()) |event| {
            if(event.type == c.SDL_QUIT) {
                return;
            }
            app.onEvent(app_data_ptr, &event);
        }

        app.onRender(app_data_ptr);
    }
}
