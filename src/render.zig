const std = @import("std");
const allocator = @import("main").allocator;
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const c = sdl.c;

pub const max_tiles = 65536; // 4 bytes per tile, 65536 tiles = 26kb


const Attrib = enum(c_uint) {
    position,
    color,
    tile_dat_ptr,
    pub const all_attributes = &[_]Attrib{.position, .color, .tile_dat_ptr};
    pub fn id(attrib: Attrib) c_uint {
        return @enumToInt(attrib);
    }
    pub fn ctype(attrib: Attrib) c.GLenum {
        return switch(attrib) {
            .position => c.GL_FLOAT,
            .color => c.GL_FLOAT,
            .tile_dat_ptr => c.GL_UNSIGNED_INT,
        };
    }
    pub fn count(attrib: Attrib) usize {
        return switch(attrib) {
            .position => 3,
            .color => 3,
            .tile_dat_ptr => 1,
        };
    }
    pub fn size(attrib: Attrib) usize {
        return switch(attrib) {
            .position => @sizeOf(c.GLfloat) * 3,
            .color => @sizeOf(c.GLfloat) * 3,
            .tile_dat_ptr => @sizeOf(c.GLuint) * 1,
        };
    }
    pub fn activate() void {
        var total: usize = 0;
        for(all_attributes) |attrib| {
            total += attrib.size();
        }
        var stride: usize = 0;
        for(all_attributes) |attrib| {
            c.glEnableVertexAttribArray(attrib.id());
            const c_count = @intCast(c.GLint, attrib.count());
            const c_total = @intCast(c.GLint, total);
            const c_stride = @intToPtr(?*const anyopaque, stride);
            if(attrib.ctype() == c.GL_UNSIGNED_INT) {
                c.glVertexAttribIPointer(attrib.id(), c_count, attrib.ctype(), c_total, c_stride);
            }else{
                c.glVertexAttribPointer(attrib.id(), c_count, attrib.ctype(), c.GL_FALSE, c_total, c_stride);
            }
            stride += attrib.size();
        }
    }
};

// why when I look up "opengl tilemap" is everyone talking about using two triangles per tile
// like why not put it all in the shader? why have to have so many vertices and deal with chunking and all that

// ok I want:
// vec3 position (x, y, z) (how to make sure stuff appears in the right layer? maybe use an ortho projection matrix)
//    i don't know how clip space works so probably I can just use an ortho projection matrix and not deal with it
// vec3 tile_position (0..w, 0..h)
// uint index (same for all six coordinates. says where in the sampler buffer the texture starts)
const vertex_shader_source = (
    \\#version 330
    \\in vec3 i_position;
    \\in vec3 i_tile_position;
    \\in uint i_tile_data_ptr;
    \\flat out uint v_tile_data_ptr;
    \\out vec4 v_color;
    \\void main() {
    \\    gl_Position = vec4( i_position, 1.0 );
    \\    v_color = vec4(i_tile_position / 10.0, 1.0);
    \\    v_tile_data_ptr = i_tile_data_ptr;
    \\}
);
const fragment_shader_source = (
    \\#version 330
    \\flat in uint v_tile_data_ptr;
    \\in vec4 v_color;
    \\uniform usamplerBuffer u_tbo_tex;
    \\out vec4 o_color;
    \\void main() {
    \\    o_color = v_color;
    \\    // texelFetch(u_tbo_tex, byte_pos / 4 (rgba))
    \\    // alternatively, we could only use the red channel and then it would just be byte_pos directly
    \\    // seems like it could be useful to have 4 bytes per thing though
    \\    //o_color = vec4(texelFetch(u_tbo_tex, 0)) / vec4(255);
    \\}
);

// when rendering:
// - if a product has been updated, use glBufferSubData to update that part of the buffer

// the vertex buffer is regenerated every frame because it's tiny so who cares

pub const Renderer = struct {
    window: *c.SDL_Window,
    world: *const game.World,

    vertex_array: c.GLuint,
    vertex_buffer: c.GLuint,
    u_tbo_tex: c.GLint,
    tiles_data_buffer: c.GLuint,
    tiles_texture: c.GLuint,

    pub fn init(window: *c.SDL_Window, world: *const game.World) !Renderer {
        var vertex_shader: c_uint = try sdl.createCompileShader(c.GL_VERTEX_SHADER, vertex_shader_source);
        var fragment_shader: c_uint = try sdl.createCompileShader(c.GL_FRAGMENT_SHADER, fragment_shader_source);

        var shader_program: c_uint = c.glCreateProgram();
        try sdl.gewrap(c.glAttachShader(shader_program, vertex_shader));
        try sdl.gewrap(c.glAttachShader(shader_program, fragment_shader));
        try sdl.gewrap(c.glBindAttribLocation(shader_program, Attrib.position.id(), "i_position"));
        try sdl.gewrap(c.glBindAttribLocation(shader_program, Attrib.color.id(), "color"));
        try sdl.gewrap(c.glLinkProgram(shader_program));

        try sdl.gewrap(c.glUseProgram(shader_program));

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
        try sdl.gewrap(c.glBufferData(c.GL_TEXTURE_BUFFER, @sizeOf(u8) * 4 * max_tiles, null, c.GL_DYNAMIC_DRAW));

        var tiles_texture: c.GLuint = undefined;
        try sdl.gewrap(c.glGenTextures(1, &tiles_texture));

        try sdl.gewrap(c.glEnable(c.GL_DEPTH_TEST));

        return .{
            .window = window,
            .world = world,

            .vertex_array = vertex_array,
            .vertex_buffer = vertex_buffer,
            .u_tbo_tex = u_tbo_tex,
            .tiles_data_buffer = tiles_data_buffer,
            .tiles_texture = tiles_texture,
        };
    }

    pub fn renderWorld(renderer: *Renderer) !void {
        try sdl.gewrap(c.glActiveTexture(c.GL_TEXTURE0));
        try sdl.gewrap(c.glBindTexture(c.GL_TEXTURE_BUFFER, renderer.tiles_texture));
        try sdl.gewrap(c.glTexBuffer(c.GL_TEXTURE_BUFFER, c.GL_RGBA8UI, renderer.tiles_data_buffer));
        try sdl.gewrap(c.glUniform1i(renderer.u_tbo_tex, 0));

        try sdl.gewrap(c.glBindVertexArray(renderer.vertex_array));
        try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, renderer.vertex_buffer));



        const vertex_buffer_data = [_]c.GLfloat{
            // xyz|tile_xyz|
            -0.5, -0.2, 0,    0, 0, 0,    @bitCast(c.GLfloat, @as(c.GLint, 6)),
            0.5, -0.5, 0,     10, 0, 0,  @bitCast(c.GLfloat, @as(c.GLint, 6)),
            0.5, 0.5, 0,      10, 10, 0, @bitCast(c.GLfloat, @as(c.GLint, 6)),
            -0.5, -0.2, 0,    0, 0, 0,    @bitCast(c.GLfloat, @as(c.GLint, 6)),
            0.5, 0.5, 0,      10, 10, 0, @bitCast(c.GLfloat, @as(c.GLint, 6)),
            -0.5, 0.5, 0,     0, 10, 0,   @bitCast(c.GLfloat, @as(c.GLint, 6)),
        };
        try sdl.gewrap(c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertex_buffer_data)), @ptrCast(?*const anyopaque, &vertex_buffer_data), c.GL_STATIC_DRAW));

        try sdl.gewrap(c.glDrawArrays(c.GL_TRIANGLES, 0, 6));
    }
};
