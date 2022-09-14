//! deals with opengl. leaky abstraction.

const std = @import("std");
const allocator = @import("main.zig").allocator;
const sdl = @import("sdl.zig");
const plat = @import("platform.zig");
const game = @import("game.zig");
const c = sdl.c;
const log = std.log.scoped(.render);


pub const max_tiles = 65536; // 4 bytes per tile, 65536 tiles = 26kb


const Attrib = enum(c_uint) {
    position,
    tile_position,
    tile_dat_ptr,
    pub const all_attributes = &[_]Attrib{.position, .tile_position, .tile_dat_ptr};
    pub fn id(attrib: Attrib) c_uint {
        return @enumToInt(attrib);
    }
    pub fn name(attrib: Attrib) [*:0]const u8 {
        return switch(attrib) {
            .position => "i_position",
            .tile_position => "i_tile_position",
            .tile_dat_ptr => "i_tile_data_ptr",
        };
    }
    pub fn ctype(attrib: Attrib) c.GLenum {
        return switch(attrib) {
            .position => c.GL_FLOAT,
            .tile_position => c.GL_FLOAT,
            .tile_dat_ptr => c.GL_UNSIGNED_INT,
        };
    }
    pub fn count(attrib: Attrib) usize {
        return switch(attrib) {
            .position => 3,
            .tile_position => 3,
            .tile_dat_ptr => 1,
        };
    }
    pub fn size(attrib: Attrib) usize {
        return switch(attrib) {
            .position => @sizeOf(c.GLfloat) * 3,
            .tile_position => @sizeOf(c.GLfloat) * 3,
            .tile_dat_ptr => @sizeOf(c.GLuint) * 1,
        };
    }
    pub fn bind(shader_prog: c_uint) !void {
        for(all_attributes) |attrib| {
            try sdl.gewrap(c.glBindAttribLocation(shader_prog, attrib.id(), attrib.name()));
        }
    }
    pub fn activate() !void {
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
                try sdl.gewrap(c.glVertexAttribIPointer(attrib.id(), c_count, attrib.ctype(), c_total, c_stride));
            }else{
                try sdl.gewrap(c.glVertexAttribPointer(attrib.id(), c_count, attrib.ctype(), c.GL_FALSE, c_total, c_stride));
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
    \\flat out int v_tile_data_ptr;
    \\out vec3 v_tile_position;
    \\out vec3 v_qposition;
    \\out float v_z;
    \\void main() {
    \\    gl_Position = vec4( i_position, 1.0 );
    \\    v_tile_data_ptr = int(i_tile_data_ptr);
    \\    v_tile_position = i_tile_position;
    \\    v_z = -i_position.z * 100.0;
    \\    v_qposition = i_position;
    \\}
);
const fragment_shader_source = (
    \\#version 330
    \\flat in int v_tile_data_ptr;
    \\in vec3 v_tile_position;
    \\in vec3 v_qposition;
    \\in float v_z;
    \\uniform usamplerBuffer u_tbo_tex;
    \\out vec4 o_color;
    \\uvec4 getMem(int ptr) {
    \\    return texelFetch(u_tbo_tex, ptr);
    \\}
    \\uvec4 getTile(int ptr, ivec3 pos, ivec3 size) {
    \\    //if(any(greaterThanEqual(pos, size)) || any(lessThan(pos, ivec3(0, 0, 0)))) {
    \\    //    return uvec4(0, 0, 0, 0); // out of bounds; return air tile
    \\    //}
    \\    return getMem(ptr + 1 + pos.x + (pos.y * size.x) + (pos.z * size.x * size.y));
    \\}
    \\void main() {
    \\    uvec4 header = getMem(v_tile_data_ptr);
    \\    ivec3 size = ivec3(header.xyz);
    \\    ivec3 pos = ivec3(floor(v_tile_position));
    \\    uvec4 tile = getTile(v_tile_data_ptr, pos, size);
    \\
    \\    o_color = vec4(0.0, 0.0, 0.0, 0.0);
    \\    if(tile.x == 0u) discard;
    \\    if(tile.x == 1u) o_color = vec4(1.0, 0.0, 0.0, 1.0);
    \\    if(tile.x == 2u) o_color = vec4(0.0, 1.0, 0.0, 1.0);
    \\    if(tile.x == 3u) o_color = vec4(0.0, 0.0, 1.0, 1.0);
    \\    if(tile.x == 4u) o_color = vec4(1.0, 1.0, 0.0, 1.0);
    \\    //o_color = vec4(float(tile.x) * 100, 0.0, 0.0, 1.0);
    \\    //o_color = vec4(float(header.x) * 100, 0.0, 0.0, 255.0) / vec4(255.0);
    \\    if(v_z <= 0.1 && v_z >= -0.1) o_color *= vec4(0.8, 0.8, 0.8, 1.0);
    \\}
);

// when rendering:
// - if a product has been updated, use glBufferSubData to update that part of the buffer

// the vertex buffer is regenerated every frame because it's tiny so who cares

pub const ProductRenderData = struct {
    id: game.ProductID,

    last_updated: usize,

    buffer_pos: usize,
    buffer_size: usize,
};

pub const Renderer = struct {
    platform: *plat.Platform,
    world: *const game.World,

    vertex_array: c.GLuint,
    vertex_buffer: c.GLuint,
    vertices: c.GLint,
    u_tbo_tex: c.GLint,
    tiles_data_buffer: c.GLuint,
    tiles_texture: c.GLuint,

    // TODO: preserve the buffer across frames and only update what is needed.
    // we have to use an allocator or something though.
    // anyway, perf is fine right now so who cares. probably only needed if we're going to
    // try to display an entire world at max zoom out
    temp_this_frame_bufidx: usize = undefined,

    product_render_data: std.ArrayList(ProductRenderData),

    pub fn init(platform: *plat.Platform, world: *const game.World) !Renderer {
        const gl_ver = try sdl.gewrap(c.glGetString(c.GL_VERSION));
        log.info("gl ver: {s}", .{std.mem.span(gl_ver)});

        var vertex_shader: c_uint = try sdl.createCompileShader(c.GL_VERTEX_SHADER, vertex_shader_source);
        var fragment_shader: c_uint = try sdl.createCompileShader(c.GL_FRAGMENT_SHADER, fragment_shader_source);

        var shader_program: c_uint = c.glCreateProgram();
        try sdl.gewrap(c.glAttachShader(shader_program, vertex_shader));
        try sdl.gewrap(c.glAttachShader(shader_program, fragment_shader));
        try Attrib.bind(shader_program);
        try sdl.gewrap(c.glLinkProgram(shader_program));

        try sdl.gewrap(c.glUseProgram(shader_program));

        var vertex_array: c.GLuint = undefined;
        try sdl.gewrap(c.glGenVertexArrays(1, &vertex_array));
        var vertex_buffer: c.GLuint = undefined;
        try sdl.gewrap(c.glGenBuffers(1, &vertex_buffer));

        try sdl.gewrap(c.glBindVertexArray(vertex_array));
        try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, vertex_buffer));

        try Attrib.activate();

        const u_tbo_tex = c.glGetUniformLocation(shader_program, "u_tbo_tex");

        var tiles_data_buffer: c.GLuint = undefined;
        try sdl.gewrap(c.glGenBuffers(1, &tiles_data_buffer));
        try sdl.gewrap(c.glBindBuffer(c.GL_TEXTURE_BUFFER, tiles_data_buffer));
        try sdl.gewrap(c.glBufferData(c.GL_TEXTURE_BUFFER, @sizeOf(u8) * 4 * max_tiles, null, c.GL_DYNAMIC_DRAW)); // &[_]u8{0} ** (@sizeOf(u8) * 4 * max_tiles)

        var tiles_texture: c.GLuint = undefined;
        try sdl.gewrap(c.glGenTextures(1, &tiles_texture));

        try sdl.gewrap(c.glEnable(c.GL_DEPTH_TEST));

        var product_render_data = std.ArrayList(ProductRenderData).init(allocator());

        return .{
            .platform = platform,
            .world = world,

            .vertex_array = vertex_array,
            .vertex_buffer = vertex_buffer,
            .vertices = 0,
            .u_tbo_tex = u_tbo_tex,
            .tiles_data_buffer = tiles_data_buffer,
            .tiles_texture = tiles_texture,

            .product_render_data = product_render_data,
        };
    }

    pub fn renderFrame(renderer: *Renderer) !void {
        try sdl.gewrap(c.glViewport(0, 0, renderer.platform.window_size[game.x], renderer.platform.window_size[game.y]));
        try sdl.gewrap(c.glClearColor(1.0, 0.0, 1.0, 0.0));
        try sdl.gewrap(c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT));

        try renderer.renderWorld();
    }

    pub fn worldToScreen(renderer: *Renderer, world_space: game.Vec3) game.Vec2f {
        _ = renderer;
        const ws_x = @intToFloat(f32, world_space[game.x]);
        const ws_y = @intToFloat(f32, world_space[game.y]);
        return game.Vec2f{
            (ws_x - 5) / 10,
            (ws_y - 5) / 10,
        };
    }

    pub fn updateProduct(renderer: *Renderer, final_rectangles: *std.ArrayList(c.GLfloat), product: game.Product) !void {
        var res_byte_data = std.ArrayList(u8).init(allocator());
        defer res_byte_data.deinit();

        const result_ptr_idx: usize = renderer.temp_this_frame_bufidx;

        try res_byte_data.appendSlice(&[_]u8{
            // width, height, depth, unused
            @intCast(u8, product.size[game.x]),
            @intCast(u8, product.size[game.y]),
            @intCast(u8, product.size[game.z]),
            0,
        });

        for(product.tiles) |tile| {
            try res_byte_data.appendSlice(&[_]u8{
                // tile_id, unused, unused, unused
                @enumToInt(tile),
                0,
                0,
                0,
            });
        }
        var z_layer: i32 = 0;
        while(z_layer < product.size[game.z]) : (z_layer += 1) {
            const tile_screen_0 = renderer.worldToScreen(product.pos);
            const tile_screen_1 = renderer.worldToScreen(product.pos + product.size);
            const tile_x0: f32 = tile_screen_0[game.x];
            const tile_x1: f32 = tile_screen_1[game.x];
            const tile_y0: f32 = tile_screen_0[game.y];
            const tile_y1: f32 = tile_screen_1[game.y];
            const tile_z: f32 = -@intToFloat(f32, product.pos[game.z] + z_layer) / 100.0;
            const tile_data_x0: f32 = 0;
            const tile_data_x1: f32 = @intToFloat(f32, product.size[game.x]);
            const tile_data_y0: f32 = 0;
            const tile_data_y1: f32 = @intToFloat(f32, product.size[game.y]);
            const tile_data_z0: f32 = @intToFloat(f32, z_layer);
            const tile_data_ptr: f32 = @bitCast(c.GLfloat, @intCast(c.GLint, result_ptr_idx));
            try final_rectangles.appendSlice(&[_]c.GLfloat{
                // xyz|tile_xyz|
                tile_x0, tile_y0, tile_z, tile_data_x0, tile_data_y0, tile_data_z0, tile_data_ptr,
                tile_x1, tile_y0, tile_z, tile_data_x1, tile_data_y0, tile_data_z0, tile_data_ptr,
                tile_x1, tile_y1, tile_z, tile_data_x1, tile_data_y1, tile_data_z0, tile_data_ptr,
                tile_x0, tile_y0, tile_z, tile_data_x0, tile_data_y0, tile_data_z0, tile_data_ptr,
                tile_x1, tile_y1, tile_z, tile_data_x1, tile_data_y1, tile_data_z0, tile_data_ptr,
                tile_x0, tile_y1, tile_z, tile_data_x0, tile_data_y1, tile_data_z0, tile_data_ptr,
            });
        }
        try sdl.gewrap(c.glBufferSubData(
            c.GL_TEXTURE_BUFFER,
            @intCast(c_long, result_ptr_idx * 4),
            @intCast(c_long, @sizeOf(f32) * res_byte_data.items.len),
            res_byte_data.items.ptr,
        ));
        renderer.temp_this_frame_bufidx += res_byte_data.items.len / 4;
    }

    pub fn updateBuffers(renderer: *Renderer) !void {
        var final_rectangles = std.ArrayList(c.GLfloat).init(allocator());
        defer final_rectangles.deinit();

        try sdl.gewrap(c.glBindBuffer(c.GL_TEXTURE_BUFFER, renderer.tiles_data_buffer));
        renderer.temp_this_frame_bufidx = 1;
        for(renderer.world.products.items) |product| {
            try renderer.updateProduct(&final_rectangles, product);
        }
        try sdl.gewrap(c.glBindTexture(c.GL_TEXTURE_BUFFER, renderer.tiles_texture));
        try sdl.gewrap(c.glTexBuffer(c.GL_TEXTURE_BUFFER, c.GL_RGBA8UI, renderer.tiles_data_buffer));

        // 2. update rectangles
        try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, renderer.vertex_buffer));
        const vertex_buffer_data = final_rectangles.items;
        try sdl.gewrap(c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, @sizeOf(c.GLfloat) * vertex_buffer_data.len), @ptrCast(?*const anyopaque, vertex_buffer_data), c.GL_STATIC_DRAW));
        renderer.vertices = @intCast(c.GLint, vertex_buffer_data.len / 7);
    }

    pub fn renderWorld(renderer: *Renderer) !void {
        try sdl.gewrap(c.glActiveTexture(c.GL_TEXTURE0));
        try renderer.updateBuffers();
        try sdl.gewrap(c.glUniform1i(renderer.u_tbo_tex, 0));
        try sdl.gewrap(c.glBindVertexArray(renderer.vertex_array));
        try sdl.gewrap(c.glDrawArrays(c.GL_TRIANGLES, 0, renderer.vertices));
    }
};
