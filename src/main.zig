const std = @import("std");
const sdl = @import("sdl.zig");
const c = sdl.c;

const Attrib = enum(c_uint) {
    position,
    color,
    pub fn id(attrib: Attrib) c_uint {
        return @enumToInt(attrib);
    }
    pub fn activate() void {
        c.glEnableVertexAttribArray(Attrib.position.id());
        c.glEnableVertexAttribArray(Attrib.color.id());

        c.glVertexAttribPointer(Attrib.position.id(), 2, c.GL_FLOAT, c.GL_FALSE, @sizeOf(f32) * 6, @intToPtr(?*const anyopaque, 4 * @sizeOf(f32)));
        c.glVertexAttribPointer(Attrib.color.id(), 4, c.GL_FLOAT, c.GL_FALSE, @sizeOf(f32) * 6, @intToPtr(?*const anyopaque, 0));
    }
};
const vertex_shader_source = (
    \\#version 330
    \\in vec2 i_position;
    \\in vec4 i_color;
    \\out vec4 v_color;
    \\void main() {
    \\    v_color = i_color;
    \\    gl_Position = vec4( i_position, 0.0, 1.0 );
    \\}
);
const fragment_shader_source = (
    \\#version 330
    \\in vec4 v_color;
    \\uniform usamplerBuffer u_tbo_tex;
    \\out vec4 o_color;
    \\void main() {
    \\    o_color = v_color;
    \\    // texelFetch(u_tbo_tex, byte_pos / 4 (rgba))
    \\    // alternatively, we could only use the red channel and then it would just be byte_pos directly
    \\    // seems like it could be useful to have 4 bytes per thing though
    \\    o_color = vec4(texelFetch(u_tbo_tex, 0)) / vec4(255);
    \\}
);

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

    var window_w: i32 = 1920 / 2;
    var window_h: i32 = 1080 / 2;
    const window: *c.SDL_Window = c.SDL_CreateWindow("Productgame", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, window_w, window_h, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_SHOWN) orelse unreachable;
    const context: c.SDL_GLContext = c.SDL_GL_CreateContext(window);

    var vertex_shader: c_uint = try sdl.createCompileShader(c.GL_VERTEX_SHADER, vertex_shader_source);
    var fragment_shader: c_uint = try sdl.createCompileShader(c.GL_FRAGMENT_SHADER, fragment_shader_source);

    var shader_program: c_uint = c.glCreateProgram();
    try sdl.gewrap(c.glAttachShader(shader_program, vertex_shader));
    try sdl.gewrap(c.glAttachShader(shader_program, fragment_shader));
    try sdl.gewrap(c.glBindAttribLocation(shader_program, Attrib.position.id(), "i_position"));
    try sdl.gewrap(c.glBindAttribLocation(shader_program, Attrib.color.id(), "color"));
    try sdl.gewrap(c.glLinkProgram(shader_program));

    try sdl.gewrap(c.glUseProgram(shader_program));

    c.SDL_SetWindowResizable(window, c.SDL_TRUE);

    var vertex_array: c.GLuint = undefined;
    try sdl.gewrap(c.glGenVertexArrays(1, &vertex_array));
    var vertex_buffer: c.GLuint = undefined;
    try sdl.gewrap(c.glGenBuffers(1, &vertex_buffer));

    try sdl.gewrap(c.glBindVertexArray(vertex_array));
    try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, vertex_buffer));

    Attrib.activate();

    const u_tbo_tex = c.glGetUniformLocation(shader_program, "u_tbo_tex");

    var tiles_data_buffer: c.GLuint = undefined;
    try sdl.gewrap(c.glGenBuffers(1, &tiles_data_buffer));
    try sdl.gewrap(c.glBindBuffer(c.GL_TEXTURE_BUFFER, tiles_data_buffer));
    const tiles_buffer_data = [_]u8{
        255, 100, 50, 255,
        0, 100, 255, 255,
        255, 255, 0, 255,
        0, 0, 255, 255,
    };
    try sdl.gewrap(c.glBufferData(c.GL_TEXTURE_BUFFER, @sizeOf(@TypeOf(tiles_buffer_data)), @ptrCast(?*const anyopaque, &tiles_buffer_data), c.GL_DYNAMIC_DRAW));

    var tiles_texture: c.GLuint = undefined;
    try sdl.gewrap(c.glGenTextures(1, &tiles_texture));

    _ = context;

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
        try sdl.gewrap(c.glEnable(c.GL_DEPTH_TEST));
        try sdl.gewrap(c.glClearColor(1.0, 0.0, 1.0, 0.0));

        try sdl.gewrap(c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT));

        try sdl.gewrap(c.glActiveTexture(c.GL_TEXTURE0));
        try sdl.gewrap(c.glBindTexture(c.GL_TEXTURE_BUFFER, tiles_texture));
        try sdl.gewrap(c.glTexBuffer(c.GL_TEXTURE_BUFFER, c.GL_RGBA8UI, tiles_data_buffer));
        try sdl.gewrap(c.glUniform1i(u_tbo_tex, 0));

        try sdl.gewrap(c.glBindVertexArray(vertex_array));
        try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, vertex_buffer));

        const vertex_buffer_data = [_]c.GLfloat{
        // rgba|xy
            1, 0, 0, 1, -0.5, -0.5,
            0, 1, 0, 1, 0.5, -0.5,
            0, 0, 1, 1, 0.5, 0.5, 

            1, 0, 0, 1, -0.5, -0.5,
            0, 0, 1, 1, 0.5, 0.5,
            1, 1, 1, 1, -0.5, 0.5,
        };
        try sdl.gewrap(c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertex_buffer_data)), @ptrCast(?*const anyopaque, &vertex_buffer_data), c.GL_DYNAMIC_DRAW));

        try sdl.gewrap(c.glDrawArrays(c.GL_TRIANGLES, 0, 6));

        c.SDL_GL_SwapWindow(window);
    }
}
