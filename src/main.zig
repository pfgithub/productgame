const std = @import("std");
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const render = @import("render.zig");
const c = sdl.c;

// https://www.khronos.org/opengl/wiki/Buffer_Texture

var global_allocator: ?std.mem.Allocator = null;
pub fn allocator() std.mem.Allocator {
    return global_allocator.?;
}

pub fn main() !void {
    main2() catch |e| switch(e) {
        error.ShaderCompilationFailed => std.os.exit(1),
        else => return e,
    };
}

pub fn main2() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if(gpa.deinit()) unreachable;
    global_allocator = gpa.allocator();

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

    var window_w: i32 = 1920 / 2;
    var window_h: i32 = 1080 / 2;
    const window: *c.SDL_Window = c.SDL_CreateWindow("Productgame", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, window_w, window_h, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE) orelse unreachable;
    const context: c.SDL_GLContext = c.SDL_GL_CreateContext(window);
    _ = context;

    var world = game.World{
        .products = &.{},
    };
    var renderer = try render.Renderer.init(window, &world);

    var fullscreen = false;

    app: while(true) {
        try sdl.glCheckError();

        var event: c.SDL_Event = undefined;
        while(c.SDL_PollEvent(&event) != 0) { // poll until all events are handled
            if(event.type == c.SDL_KEYDOWN) {
                switch(event.key.keysym.sym) {
                    c.SDLK_ESCAPE => {},
                    'f' => {
                        fullscreen =! fullscreen;
                        sdl.sewrap(c.SDL_SetWindowFullscreen(window, if(fullscreen) c.SDL_WINDOW_FULLSCREEN_DESKTOP else 0)) catch {
                            fullscreen =! fullscreen;
                        };
                    },
                    else => {},
                }
            }else if(event.type == c.SDL_WINDOWEVENT) {
                switch(event.window.event) {
                    c.SDL_WINDOWEVENT_RESIZED => {
                        window_w = event.window.data1;
                        window_h = event.window.data2;
                    },
                    else => {},
                }
            }else if(event.type == c.SDL_QUIT) {
                break :app;
            }
        }

        try sdl.gewrap(c.glViewport(0, 0, window_w, window_h));
        try sdl.gewrap(c.glClearColor(1.0, 0.0, 1.0, 0.0));
        try sdl.gewrap(c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT));

        try renderer.renderWorld();

        c.SDL_GL_SwapWindow(window);
    }
}
