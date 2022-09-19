//! deals with sdl. leaky abstraction.

const std = @import("std");
const allocator = @import("main").allocator;
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const math = @import("math.zig");
const c = sdl.c;
const log = std.log.scoped(.platform);

const x = math.x;
const y = math.y;
const z = math.z;

extern fn enable_inertial_scroll() void;

pub const Platform = struct {
    window: *c.SDL_Window,

    window_size: math.Vec2i,
    mouse_captured: bool = false,
    capture_enterpos: math.Vec2f = math.Vec2f{0, 0},

    pub fn init() !Platform {
        var runtime_version: c.SDL_version = undefined;
        c.SDL_GetVersion(&runtime_version);
        log.info("sdl ver: {d}.{d}.{d} (compiled for {d}.{d}.{d})", .{
            runtime_version.major, runtime_version.minor, runtime_version.patch,
            c.SDL_MAJOR_VERSION, c.SDL_MINOR_VERSION, c.SDL_PATCHLEVEL,
        });

        try sdl.sewrap(c.SDL_Init(c.SDL_INIT_VIDEO));

        // - for mac trackpad gestures
        // if(c.SDL_SetHint( c.SDL_HINT_MOUSE_TOUCH_EVENTS, "1" ) == c.SDL_FALSE) {
        //     log.info("Emouse_touch_events 0?", .{});
        // }

        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_DOUBLEBUFFER, 1 ));
        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_ACCELERATED_VISUAL, 1 ));
        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_RED_SIZE, 8 ));
        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_GREEN_SIZE, 8 ));
        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_BLUE_SIZE, 8 ));
        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_ALPHA_SIZE, 8 ));

        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_CONTEXT_MAJOR_VERSION, 3 ));
        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_CONTEXT_MINOR_VERSION, 2 ));
        try sdl.sewrap(c.SDL_GL_SetAttribute( c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE ));

        const multisample = @import("builtin").os.tag != .macos; // it's not working on mac for some reason?
        // it slows the rendering down but doesn't display the multisampled output
        if(multisample) {
            try sdl.sewrap(c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1));
            try sdl.sewrap(c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 16));
        }

        var window_size = math.Vec2i{1920 / 2, 1080 / 2};
        const window: *c.SDL_Window = c.SDL_CreateWindow(
            "Productgame",
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            window_size[x],
            window_size[y],
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        ) orelse unreachable;
        const context: c.SDL_GLContext = c.SDL_GL_CreateContext(window);
        _ = context;

        if(@import("builtin").os.tag == .macos) {
            enable_inertial_scroll();
        }

        return .{
            .window = window,
            .window_size = window_size,
        };
    }

    pub fn startCaptureMouse(platform: *Platform) !void {
        try sdl.sewrap(c.SDL_SetRelativeMouseMode(c.SDL_TRUE));
        platform.mouse_captured = true;
        var ep_x: i32 = 0;
        var ep_y: i32 = 0;
        _ = c.SDL_GetMouseState(&ep_x, &ep_y);
        platform.capture_enterpos = math.Vec2f{
            @intToFloat(f64, ep_x) / @intToFloat(f64, platform.window_size[x]),
            @intToFloat(f64, ep_y) / @intToFloat(f64, platform.window_size[y]),
        };
    }
    pub fn stopCaptureMouse(platform: *Platform) !void {
        platform.mouse_captured = false;
        try sdl.sewrap(c.SDL_SetRelativeMouseMode(c.SDL_FALSE));
        const tx: i32 = @floatToInt(i32, platform.capture_enterpos[x] * @intToFloat(f64, platform.window_size[x]));
        const ty: i32 = @floatToInt(i32, platform.capture_enterpos[y] * @intToFloat(f64, platform.window_size[y]));
        c.SDL_WarpMouseInWindow(platform.window, tx, ty);
    }

    pub fn setFullscreen(platform: *Platform, fullscreen: bool) !void {
        try sdl.sewrap(c.SDL_SetWindowFullscreen(platform.window, if(fullscreen) c.SDL_WINDOW_FULLSCREEN_DESKTOP else 0));
    }

    pub fn pollEvent(platform: *Platform) ?c.SDL_Event {
        var event: c.SDL_Event = undefined;
        if(c.SDL_PollEvent(&event) == 0) return null;

        if(event.type == c.SDL_WINDOWEVENT) {
            if(event.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                platform.window_size = math.Vec2i{
                    event.window.data1,
                    event.window.data2,
                };
            }
        }

        return event;
    }

    pub fn present(platform: *Platform) void {
        c.SDL_GL_SwapWindow(platform.window);
    }
};