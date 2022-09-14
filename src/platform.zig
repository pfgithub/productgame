//! deals with sdl. leaky abstraction.

const std = @import("std");
const allocator = @import("main").allocator;
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const c = sdl.c;
const log = std.log.scoped(.platform);

pub const Platform = struct {
    window: *c.SDL_Window,

    window_size: game.Vec2,

    pub fn init() !Platform {
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

        const multisample = true;
        if(multisample) {
            try sdl.sewrap(c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLEBUFFERS, 1));
            try sdl.sewrap(c.SDL_GL_SetAttribute(c.SDL_GL_MULTISAMPLESAMPLES, 16));
        }

        var window_size = game.Vec2{1920 / 2, 1080 / 2};
        const window: *c.SDL_Window = c.SDL_CreateWindow(
            "Productgame",
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            window_size[game.x],
            window_size[game.y],
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        ) orelse unreachable;
        const context: c.SDL_GLContext = c.SDL_GL_CreateContext(window);
        _ = context;

        return .{
            .window = window,
            .window_size = window_size,
        };
    }

    pub fn setFullscreen(platform: *Platform, fullscreen: bool) !void {
        try sdl.sewrap(c.SDL_SetWindowFullscreen(platform.window, if(fullscreen) c.SDL_WINDOW_FULLSCREEN_DESKTOP else 0));
    }

    pub fn pollEvent(platform: *Platform) ?c.SDL_Event {
        var event: c.SDL_Event = undefined;
        if(c.SDL_PollEvent(&event) == 0) return null;

        if(event.type == c.SDL_WINDOWEVENT) {
            if(event.window.event == c.SDL_WINDOWEVENT_RESIZED) {
                platform.window_size = game.Vec2{
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