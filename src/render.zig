//! deals with opengl. leaky abstraction.

const std = @import("std");
const allocator = @import("main.zig").allocator;
const sdl = @import("sdl.zig");
const plat = @import("platform.zig");
const game = @import("game.zig");
const c = sdl.c;
const log = std.log.scoped(.render);


pub const max_tiles = 65536; // 4 bytes per tile, 65536 tiles = 26kb


// offset: @offsetOf(i_position)
// offset: @offsetOf(i_tile_position)
// offset: @offsetOf(i_tile_data_ptr)
// stride: @sizeOf

// strgen:
fn attribTypeStr(comptime a: type) []const u8 {
    if(a == [3]c.GLfloat) return "vec3";
    if(a == c.GLuint) return "uint";
    @compileError("TODO support type");
}
fn attribFields(comptime a: type) []const AttribTypeInfo {
    var infos: []const AttribTypeInfo = &.{};
    for(std.meta.fields(a)) |field, i| {
        infos = infos ++ &[_]AttribTypeInfo{
            attribTypeInfo(i, field.name, field.field_type, @sizeOf(a), @offsetOf(a, field.name)),
        };
    }
    return infos;
}
fn shaderInputCodegen(comptime a: type) []const u8 {
    var res: []const u8 = "";
    for(attribFields(a)) |attribute, i| {
        if(i != 0) res = res ++ " ";
        res = res ++ "in " ++ attribute.glsl_type_str ++ " " ++ attribute.name ++ ";";
    }
    return res;
}
const AttribTypeMode = enum{int, float};
const AttribTypeInfo = struct {
    id: c.GLuint,
    name: [:0]const u8,
    count: c.GLint,
    cenum: c.GLenum,
    mode: AttribTypeMode,
    stride: c.GLsizei,
    offset: ?*anyopaque,

    glsl_type_str: []const u8,
};
fn attribTypeCountCenumMode(comptime a: type) struct {count: c.GLint, cenum: c.GLenum, mode: AttribTypeMode} {
    if(a == [3]c.GLfloat) return .{.count = 3, .cenum = c.GL_FLOAT, .mode = .float};
    if(a == c.GLuint) return .{.count = 1, .cenum = c.GL_UNSIGNED_INT, .mode = .int};
    @compileError("todo support type");
}
fn attribTypeInfo(i: usize, name: []const u8, comptime a: type, stride: usize, offset: usize) AttribTypeInfo {
    const c_name: [:0]const u8 = (name ++ "\x00")[0..name.len:0];
    const c_id = @intCast(c.GLuint, i);
    const c_stride = @intCast(c.GLsizei, stride);
    const c_offset = @intToPtr(?*anyopaque, offset);
    const cmodes = attribTypeCountCenumMode(a);
    return AttribTypeInfo{
        .count = cmodes.count,
        .cenum = cmodes.cenum,
        .mode = cmodes.mode,

        .id = c_id,
        .name = c_name,
        .stride = c_stride,
        .offset = c_offset,
        .glsl_type_str = attribTypeStr(a),
    };
}
fn shaderBindAttributes(comptime shader: type, shader_prog: c_uint) !void {
    for(comptime attribFields(shader.Vertex)) |attrib| {
        try sdl.gewrap(c.glBindAttribLocation(shader_prog, attrib.id, attrib.name.ptr));
    }
}
fn shaderActivateAttributes(comptime shader: type) !void {
    for(comptime attribFields(shader.Vertex)) |attrib| {
        c.glEnableVertexAttribArray(attrib.id);
        switch(attrib.mode) {
            .int => try sdl.gewrap(c.glVertexAttribIPointer(attrib.id, attrib.count, attrib.cenum, attrib.stride, attrib.offset)),
            .float => try sdl.gewrap(c.glVertexAttribPointer(attrib.id, attrib.count, attrib.cenum, c.GL_FALSE, attrib.stride, attrib.offset)),
        }
    }
}

// why when I look up "opengl tilemap" is everyone talking about using two triangles per tile
// like why not put it all in the shader? why have to have so many vertices and deal with chunking and all that

// ok I want:
// vec3 position (x, y, z) (how to make sure stuff appears in the right layer? maybe use an ortho projection matrix)
//    i don't know how clip space works so probably I can just use an ortho projection matrix and not deal with it
// vec3 tile_position (0..w, 0..h)
// uint index (same for all six coordinates. says where in the sampler buffer the texture starts)
const TileShader = struct {
    const Vertex = struct {
        i_position: [3]c.GLfloat,
        i_tile_position: [3]c.GLfloat,
        i_tile_data_ptr: c.GLuint,
    };
    const vertex_source = (
        \\#version 330
        ++ "\n" ++ shaderInputCodegen(Vertex) ++ "\n" ++
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
    const fragment_source = (
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
};

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

        var vertex_shader: c_uint = try sdl.createCompileShader(c.GL_VERTEX_SHADER, TileShader.vertex_source);
        var fragment_shader: c_uint = try sdl.createCompileShader(c.GL_FRAGMENT_SHADER, TileShader.fragment_source);

        var shader_program: c_uint = c.glCreateProgram();
        try sdl.gewrap(c.glAttachShader(shader_program, vertex_shader));
        try sdl.gewrap(c.glAttachShader(shader_program, fragment_shader));
        try shaderBindAttributes(TileShader, shader_program);
        try sdl.gewrap(c.glLinkProgram(shader_program));
        try sdl.gewrap(c.glUseProgram(shader_program));

        var vertex_array: c.GLuint = undefined;
        try sdl.gewrap(c.glGenVertexArrays(1, &vertex_array));
        var vertex_buffer: c.GLuint = undefined;
        try sdl.gewrap(c.glGenBuffers(1, &vertex_buffer));

        try sdl.gewrap(c.glBindVertexArray(vertex_array));
        try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, vertex_buffer));

        try shaderActivateAttributes(TileShader);

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

    pub fn updateProduct(renderer: *Renderer, final_rectangles: *std.ArrayList(TileShader.Vertex), product: game.Product) !void {
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
            const tile_data_ptr: c.GLuint = @intCast(c.GLuint, result_ptr_idx);
            try final_rectangles.appendSlice(&[_]TileShader.Vertex{
                .{.i_position = [_]f32{tile_x0, tile_y0, tile_z}, .i_tile_position = [_]f32{tile_data_x0, tile_data_y0, tile_data_z0}, .i_tile_data_ptr = tile_data_ptr},
                .{.i_position = [_]f32{tile_x1, tile_y0, tile_z}, .i_tile_position = [_]f32{tile_data_x1, tile_data_y0, tile_data_z0}, .i_tile_data_ptr = tile_data_ptr},
                .{.i_position = [_]f32{tile_x1, tile_y1, tile_z}, .i_tile_position = [_]f32{tile_data_x1, tile_data_y1, tile_data_z0}, .i_tile_data_ptr = tile_data_ptr},
                .{.i_position = [_]f32{tile_x0, tile_y0, tile_z}, .i_tile_position = [_]f32{tile_data_x0, tile_data_y0, tile_data_z0}, .i_tile_data_ptr = tile_data_ptr},
                .{.i_position = [_]f32{tile_x1, tile_y1, tile_z}, .i_tile_position = [_]f32{tile_data_x1, tile_data_y1, tile_data_z0}, .i_tile_data_ptr = tile_data_ptr},
                .{.i_position = [_]f32{tile_x0, tile_y1, tile_z}, .i_tile_position = [_]f32{tile_data_x0, tile_data_y1, tile_data_z0}, .i_tile_data_ptr = tile_data_ptr},
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
        var final_rectangles = std.ArrayList(TileShader.Vertex).init(allocator());
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
        try sdl.gewrap(c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, @sizeOf(TileShader.Vertex) * final_rectangles.items.len), @ptrCast(?*const anyopaque, final_rectangles.items), c.GL_STATIC_DRAW));
        renderer.vertices = @intCast(c.GLint, final_rectangles.items.len);
    }

    pub fn renderWorld(renderer: *Renderer) !void {
        try sdl.gewrap(c.glActiveTexture(c.GL_TEXTURE0));
        try renderer.updateBuffers();
        try sdl.gewrap(c.glUniform1i(renderer.u_tbo_tex, 0));
        try sdl.gewrap(c.glBindVertexArray(renderer.vertex_array));
        try sdl.gewrap(c.glDrawArrays(c.GL_TRIANGLES, 0, renderer.vertices));
    }
};
