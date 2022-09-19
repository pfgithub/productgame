//! deals with opengl. leaky abstraction.

const std = @import("std");
const allocator = @import("main.zig").allocator;
const sdl = @import("sdl.zig");
const plat = @import("platform.zig");
const game = @import("game.zig");
const math = @import("math.zig");
const c = sdl.c;
const log = std.log.scoped(.render);

const Vec2f = math.Vec2f;
const Vec3f = math.Vec3f;
const Vec2i = math.Vec2i;
const Vec3i = math.Vec3i;

const x = math.x;
const y = math.y;
const z = math.z;

pub const max_tiles = 65536; // 4 bytes per tile, 65536 tiles = 26kb

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
    var res: []const u8 = "#line 0 5000\n";
    for(attribFields(a)) |attribute| {
        res = res ++ "in " ++ attribute.glsl_type_str ++ " " ++ attribute.name ++ ";\n";
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
        \\#define VERTEX_SHADER
    );
    const fragment_source = (
        \\#version 330
        ++ "\n" ++ tile_ids_code ++ "\n" ++
        \\#define FRAGMENT_SHADER
    );
};

fn srcStr(comptime srcloc: std.builtin.SourceLocation) []const u8 {
    return "#line " ++ intStr(srcloc.line + 1) ++ " \"" ++ srcloc.file ++ "\"";
}
fn intStr(comptime int_: comptime_int) []const u8 {
    var int = int_;
    var res: []const u8 = "";
    if(int < 0) {
        res = "-" ++ res;
        int = -int;
    }
    if(int == 0) {
        res = res ++ "0";
    } else while(int > 0) {
        const digit = int % 10;
        int /= 10;
        res = res ++ &[_]u8{digit + '0'};
    }
    return res;
}
const tile_ids_code = blk: {
    var res: []const u8 = "#line 0 4000\n";
    // std.fmt.comptimePrint
    for(std.meta.tags(game.TileID)) |tile_id| {
        res = res ++ "#define TILE_" ++ @tagName(tile_id) ++ " " ++ intStr(@enumToInt(tile_id)) ++ "u\n";
    }
    res = res ++ "#define CONST_height " ++ tile_height_str ++ "\n";
    break :blk res;
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

pub const tile_height_str = "0.2";
pub const tile_height: comptime_float = std.fmt.parseFloat(f128, tile_height_str) catch unreachable;

pub const Renderer = struct {
    platform: *plat.Platform,
    world: *const game.World,

    vertex_array: c.GLuint,
    vertex_buffer: c.GLuint,
    vertices: c.GLint,
    shader_program: c.GLuint,
    u_tbo_tex: c.GLint,
    tiles_data_buffer: c.GLuint,
    tiles_texture: c.GLuint,

    timestamp: f64 = 0,
    frame_start_timestamp: f64 = 0,
    frame_start_id: usize = 1,

    camera_height: i32 = 0,
    camera_pos: Vec2f = Vec2f{0.0, 0.0},
    camera_scale_factor: f64 = 0.0,

    // TODO: preserve the buffer across frames and only update what is needed.
    // we have to use an allocator or something though.
    // anyway, perf is fine right now so who cares. probably only needed if we're going to
    // try to display an entire world at max zoom out
    temp_this_frame_bufidx: usize = undefined,

    product_render_data: std.ArrayList(ProductRenderData),

    pub fn recompileShaders(renderer: *Renderer) !void {
        log.info("{s}ompiling shaders…", .{if(renderer.shader_program == 0) "C" else "Rec"});

        const shader_file_source = try std.fs.cwd().readFileAlloc(allocator(), "src/tile.frag", std.math.maxInt(usize));
        defer allocator().free(shader_file_source);

        var vertex_source_al = std.ArrayList(u8).init(allocator());
        defer vertex_source_al.deinit();
        try vertex_source_al.appendSlice(TileShader.vertex_source);
        try vertex_source_al.appendSlice("\n");
        try vertex_source_al.appendSlice(shader_file_source);
        var vertex_shader: c_uint = try sdl.createCompileShader(c.GL_VERTEX_SHADER, vertex_source_al.items);

        var fragment_source_al = std.ArrayList(u8).init(allocator());
        defer fragment_source_al.deinit();
        try fragment_source_al.appendSlice(TileShader.fragment_source);
        try fragment_source_al.appendSlice("\n");
        try fragment_source_al.appendSlice(shader_file_source);
        var fragment_shader: c_uint = try sdl.createCompileShader(c.GL_FRAGMENT_SHADER, fragment_source_al.items);

        var shader_program: c_uint = c.glCreateProgram();
        try sdl.gewrap(c.glAttachShader(shader_program, vertex_shader));
        try sdl.gewrap(c.glAttachShader(shader_program, fragment_shader));
        try shaderBindAttributes(TileShader, shader_program);
        try sdl.gewrap(c.glLinkProgram(shader_program));
        try sdl.gewrap(c.glUseProgram(shader_program));
        errdefer {
            if(renderer.shader_program != 0) {
                // TODO glDeleteShader(the shaders)
                sdl.gewrap(c.glUseProgram(renderer.shader_program)) catch unreachable;
            }
        }

        const u_tbo_tex = c.glGetUniformLocation(shader_program, "u_tbo_tex");

        if(renderer.shader_program != 0) {
            sdl.gewrap(c.glDeleteProgram(renderer.shader_program)) catch unreachable;
        }
        renderer.shader_program = shader_program;
        renderer.u_tbo_tex = u_tbo_tex;
        log.info("✓ Done", .{});
    }

    pub fn init(platform: *plat.Platform, world: *const game.World) !Renderer {
        const gl_ver = try sdl.gewrap(c.glGetString(c.GL_VERSION));
        log.info("gl ver: {s}", .{std.mem.span(gl_ver)});

        var vertex_array: c.GLuint = undefined;
        try sdl.gewrap(c.glGenVertexArrays(1, &vertex_array));
        var vertex_buffer: c.GLuint = undefined;
        try sdl.gewrap(c.glGenBuffers(1, &vertex_buffer));

        try sdl.gewrap(c.glBindVertexArray(vertex_array));
        try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, vertex_buffer));

        try shaderActivateAttributes(TileShader);

        var tiles_data_buffer: c.GLuint = undefined;
        try sdl.gewrap(c.glGenBuffers(1, &tiles_data_buffer));
        try sdl.gewrap(c.glBindBuffer(c.GL_TEXTURE_BUFFER, tiles_data_buffer));
        try sdl.gewrap(c.glBufferData(c.GL_TEXTURE_BUFFER, @sizeOf(u8) * 4 * max_tiles, null, c.GL_DYNAMIC_DRAW)); // &[_]u8{0} ** (@sizeOf(u8) * 4 * max_tiles)

        var tiles_texture: c.GLuint = undefined;
        try sdl.gewrap(c.glGenTextures(1, &tiles_texture));

        try sdl.gewrap(c.glEnable(c.GL_DEPTH_TEST));
        try sdl.gewrap(c.glEnable(c.GL_FRAMEBUFFER_SRGB));
        // only enable if we need it
        // try sdl.gewrap(c.glEnable(c.GL_BLEND));
        // try sdl.gewrap(c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA));

        var product_render_data = std.ArrayList(ProductRenderData).init(allocator());

        return .{
            .platform = platform,
            .world = world,

            .vertex_array = vertex_array,
            .vertex_buffer = vertex_buffer,
            .vertices = 0,
            .shader_program = 0,
            .u_tbo_tex = 0,
            .tiles_data_buffer = tiles_data_buffer,
            .tiles_texture = tiles_texture,

            .product_render_data = product_render_data,
        };
    }

    pub fn camera_scale(renderer: *Renderer) f64 {
        // 2 → 4
        // 1 → 2
        // 0 → 1
        // -1 → ½
        // -2 → ¼
        // ah: 2^x

        return std.math.pow(f64, 2.0, renderer.camera_scale_factor / 2.0) * 0.1;

        // divide result by 10 (so 0 = 0.1)
    }

    pub fn renderFrame(renderer: *Renderer, timestamp: f64) !void {
        renderer.timestamp = timestamp;

        try sdl.gewrap(c.glViewport(0, 0, renderer.platform.window_size[x], renderer.platform.window_size[y]));
        try sdl.gewrap(c.glClearColor(1.0, 0.0, 1.0, 0.0));
        try sdl.gewrap(c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT));

        try renderer.renderWorld();
    }

    // the opposite of worldToScreen
    // screen space is [-1..1], world space is tile coordinates
    pub fn screenToWorld(renderer: *Renderer, screen_space: Vec2f, height: f64) Vec3f {
        var res = screen_space;
        res -= renderer.camera_pos;
        const ratio = @intToFloat(f64, renderer.platform.window_size[x]) / @intToFloat(f64, renderer.platform.window_size[y]);
        if(ratio > 1.0) {
            res[x] /= 1 / ratio;
        }else{
            res[y] /= ratio;
        }
        res = Vec2f{
            res[x] / renderer.camera_scale(),
            -res[y] / renderer.camera_scale(),
        };
        const yoffset: f64 = -height * tile_height;
        res[y] -= yoffset;
        return Vec3f{
            res[x],
            res[y],
            height,
        };
    }

    pub fn worldToScreen(renderer: *Renderer, world_space: Vec3f) Vec2f {
        var res = Vec2f{
            world_space[x],
            world_space[y],
        };
        const yoffset: f64 = -world_space[z] * tile_height;
        res[y] += yoffset;
        res = Vec2f{
            res[x] * renderer.camera_scale(),
            -res[y] * renderer.camera_scale(),
        };
        // res += renderer.camera_pos;
        const ratio = @intToFloat(f64, renderer.platform.window_size[x]) / @intToFloat(f64, renderer.platform.window_size[y]);
        if(ratio > 1.0) {
            res[x] *= 1 / ratio;
        }else{
            res[y] *= ratio;
        }
        res += renderer.camera_pos;
        return res;
    }

    pub fn updateProduct(renderer: *Renderer, final_rectangles: *std.ArrayList(TileShader.Vertex), product: game.Product, progress: f64) !void {
        var res_byte_data = std.ArrayList(u8).init(allocator());
        defer res_byte_data.deinit();

        const result_ptr_idx: usize = renderer.temp_this_frame_bufidx;

        try res_byte_data.appendSlice(&[_]u8{
            // width, height, depth, unused
            @intCast(u8, product.size[x]),
            @intCast(u8, product.size[y]),
            @intCast(u8, product.size[z]),
            0,
        });

        for(product.tiles) |tile| {
            try res_byte_data.appendSlice(&[_]u8{
                @enumToInt(tile.id),
                tile.data_1,
                tile.data_2,
                tile.data_3,
            });
        }
        var z_layer: i32 = 0;
        while(z_layer < product.size[z]) : (z_layer += 1) {
            const our_progress: f64 = if(product.last_moved != renderer.frame_start_id) 1.0 else progress;
            const pos_anim = interpolateVec3f(our_progress, vec3iToF(product.moved_from), vec3iToF(product.pos)) + Vec3f{0.0, 0.0, @intToFloat(f64, z_layer)};
            const tile_screen_0 = renderer.worldToScreen(pos_anim - Vec3f{1.0, 1.0, 0.0});
            const tile_screen_1 = renderer.worldToScreen(pos_anim + vec3iToF(Vec3i{product.size[x], product.size[y], 0.0}) + Vec3f{1.0, 1.0, 0.0});
            // TODO: for precision, crop tile pos to [-1..1] and update tile_data to the cropped values
            const pos_z: c.GLfloat = @floatCast(c.GLfloat, -@intToFloat(f64, product.pos[z] + z_layer) / 100.0);
            const extra = Vec2f{1, 1};
            try final_rectangles.appendSlice(&rectVertices(
                vec2fToGlf(tile_screen_0),
                vec2fToGlf(tile_screen_1),
                pos_z,
                vec2fToGlf(Vec2f{0, 0} - extra),
                vec2fToGlf(Vec2f{@intToFloat(f64, product.size[x]), @intToFloat(f64, product.size[y])} + extra),
                @intToFloat(c.GLfloat, z_layer),
                @intCast(c.GLuint, result_ptr_idx),
            ));
        }
        if((result_ptr_idx * 4 + res_byte_data.items.len) / 4 >= max_tiles) {
            return error.TooManyTiles;
        }
        try sdl.gewrap(c.glBufferSubData(
            c.GL_TEXTURE_BUFFER,
            @intCast(c_long, result_ptr_idx * 4),
            @intCast(c_long, @sizeOf(u8) * res_byte_data.items.len),
            res_byte_data.items.ptr,
        ));
        renderer.temp_this_frame_bufidx += res_byte_data.items.len / 4;
    }

    fn rectVertices(pos_ul: Vec2glf, pos_br: Vec2glf, pos_z: c.GLfloat, tile_ul: Vec2glf, tile_br: Vec2glf, tile_z: c.GLfloat, dptr: c.GLuint) [6]TileShader.Vertex {
        return [6]TileShader.Vertex{
            .{.i_position = [_]c.GLfloat{pos_ul[x], pos_ul[y], pos_z}, .i_tile_position = [_]c.GLfloat{tile_ul[x], tile_ul[y], tile_z}, .i_tile_data_ptr = dptr},
            .{.i_position = [_]c.GLfloat{pos_br[x], pos_ul[y], pos_z}, .i_tile_position = [_]c.GLfloat{tile_br[x], tile_ul[y], tile_z}, .i_tile_data_ptr = dptr},
            .{.i_position = [_]c.GLfloat{pos_br[x], pos_br[y], pos_z}, .i_tile_position = [_]c.GLfloat{tile_br[x], tile_br[y], tile_z}, .i_tile_data_ptr = dptr},
            .{.i_position = [_]c.GLfloat{pos_ul[x], pos_ul[y], pos_z}, .i_tile_position = [_]c.GLfloat{tile_ul[x], tile_ul[y], tile_z}, .i_tile_data_ptr = dptr},
            .{.i_position = [_]c.GLfloat{pos_br[x], pos_br[y], pos_z}, .i_tile_position = [_]c.GLfloat{tile_br[x], tile_br[y], tile_z}, .i_tile_data_ptr = dptr},
            .{.i_position = [_]c.GLfloat{pos_ul[x], pos_br[y], pos_z}, .i_tile_position = [_]c.GLfloat{tile_ul[x], tile_br[y], tile_z}, .i_tile_data_ptr = dptr},
        };
    }

    pub fn updateBuffers(renderer: *Renderer, progress: f64) !void {
        var final_rectangles = std.ArrayList(TileShader.Vertex).init(allocator());
        defer final_rectangles.deinit();

        try sdl.gewrap(c.glBindBuffer(c.GL_TEXTURE_BUFFER, renderer.tiles_data_buffer));
        const header_len = 4;
        // 1. update tiles in data buffer
        renderer.temp_this_frame_bufidx = header_len;
        for(renderer.world.products.items) |product| {
            try renderer.updateProduct(&final_rectangles, product, progress);
        }

        const under_cursor = renderer.screenToWorld(Vec2f{0.0, 0.0}, -1.0);
        // so I guess we can get the object under the cursor and then use that to determine the id based 
        // on our data here

        // 2. add the ui layer
        if(renderer.platform.mouse_captured) {
            var xsq: c.GLfloat = 1.0;
            var ysq: c.GLfloat = 1.0;
            const ratio = @intToFloat(c.GLfloat, renderer.platform.window_size[x]) / @intToFloat(c.GLfloat, renderer.platform.window_size[y]);
            if(ratio > 1.0) {
                xsq *= ratio;
            }else{
                ysq *= 1 / ratio;
            }
            try final_rectangles.appendSlice(&rectVertices(
                .{-1, -1}, .{1, 1}, -0x0.FFF, .{-xsq, -ysq}, .{xsq, ysq}, 0, 0,
            ));
        }

        // 3. update data buffer header
        const header_data: []const u8 = &[header_len * 4]u8{
            // unused
            0, 0, 0, 0,
            // progress
            std.math.lossyCast(u8, progress * 255.0), 0, 0, 0,
            // t_x, t_y, t_z, FLAGS
            std.math.lossyCast(u8, under_cursor[x] - 5.0),
            std.math.lossyCast(u8, under_cursor[y] - 5.0),
            std.math.lossyCast(u8, under_cursor[z] - 5.0),
            0,
            // t_id
            0, 0, 0, if(renderer.platform.mouse_captured) 4 else 0,
        };
        try sdl.gewrap(c.glBufferSubData(
            c.GL_TEXTURE_BUFFER,
            0,
            @intCast(c_long, @sizeOf(u8) * header_data.len),
            header_data.ptr,
        ));
        try sdl.gewrap(c.glBindTexture(c.GL_TEXTURE_BUFFER, renderer.tiles_texture));
        try sdl.gewrap(c.glTexBuffer(c.GL_TEXTURE_BUFFER, c.GL_RGBA8UI, renderer.tiles_data_buffer));

        // 4. update vertices
        try sdl.gewrap(c.glBindBuffer(c.GL_ARRAY_BUFFER, renderer.vertex_buffer));
        try sdl.gewrap(c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, @sizeOf(TileShader.Vertex) * final_rectangles.items.len), @ptrCast(?*const anyopaque, final_rectangles.items), c.GL_STATIC_DRAW));
        renderer.vertices = @intCast(c.GLint, final_rectangles.items.len);
    }

    pub fn renderWorld(renderer: *Renderer) !void {
        if(renderer.shader_program == 0) try renderer.recompileShaders();

        if(renderer.frame_start_id != renderer.world.physics_time) {
            renderer.frame_start_id = renderer.world.physics_time;
            renderer.frame_start_timestamp = renderer.timestamp;
        }

        const progress = smoothstep(renderer.frame_start_timestamp, renderer.frame_start_timestamp + 100, renderer.timestamp);
    
        try sdl.gewrap(c.glActiveTexture(c.GL_TEXTURE0));
        try renderer.updateBuffers(progress);
        try sdl.gewrap(c.glUniform1i(renderer.u_tbo_tex, 0));
        try sdl.gewrap(c.glBindVertexArray(renderer.vertex_array));
        try sdl.gewrap(c.glDrawArrays(c.GL_TRIANGLES, 0, renderer.vertices));
    }
};

fn interpolateVec3f(t: f64, a: Vec3f, b: Vec3f) Vec3f {
    return (b - a) * @splat(3, t) + a;
}

fn smoothstep(min: f64, max: f64, value: f64) f64 {
    var v = (value - min) / (max - min);
    v = std.math.min(v, 1.0);
    v = std.math.max(v, 0.0);
    v = v * v * (3.0 - 2.0 * v);

    return @floatCast(f64, v);
}

fn vec3iToF(a: Vec3i) Vec3f {
    return Vec3f{
        @intToFloat(f64, a[x]),
        @intToFloat(f64, a[y]),
        @intToFloat(f64, a[z]),
    };
}
fn vec2fToGlf(a: Vec2f) Vec2glf {
    return Vec2glf{
        @floatCast(c.GLfloat, a[x]),
        @floatCast(c.GLfloat, a[y]),
    };
}
// vecSwizzle(vec, anytype)
// vecSwizzle(myvec, .xz) => vec2(vectype(myvec)){x, z}
const Vec2glf = std.meta.Vector(2, c.GLfloat);