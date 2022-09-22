const std = @import("std");
const allocator = @import("main.zig").allocator;
pub const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdint.h");
    @cInclude("assert.h");
    @cDefine("GL_GLEXT_PROTOTYPES", "");
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_opengl.h");
});
const log = std.log.scoped(.sdl);

pub fn pollEvent() ?c.SDL_Event {
    var event: c.SDL_Event = undefined;
    if(c.SDL_PollEvent(&event) == 0) return null;

    return event;
}

pub fn sewrap(return_value: c_int) !void {
    if(return_value != 0) {
        log.err("SDL Error: {s}", .{std.mem.span(c.SDL_GetError())});
        return error.SDL_Error;
    }
}

pub fn createCompileShader(kind: c_uint, source: []const u8) !c_uint {
    const shader = try gewrap(c.glCreateShader(kind));

    try gewrap(c.glShaderSource(shader, 1, &source.ptr, &@intCast(c_int, source.len)));
    errdefer c.glDeleteShader(shader);

    try gewrap(c.glCompileShader(shader));

    var status: c.GLint = undefined;
    try gewrap(c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status));
    if(status == c.GL_FALSE) {
        var max_length: c.GLint = undefined;
        try gewrap(c.glGetShaderiv(shader, c.GL_INFO_LOG_LENGTH, &max_length));

        const err_log = allocator().alloc(c.GLchar, @intCast(usize, max_length)) catch @panic("oom");
        defer allocator().free(err_log);

        var str_len: c.GLint = undefined;
        c.glGetShaderInfoLog(shader, @intCast(c.GLint, err_log.len), &str_len, err_log.ptr);

        log.err("GL Error: Shader compilation failed", .{});

        std.debug.print("--- msg ---\n{s}", .{err_log[0..@intCast(usize, str_len)]});

        return error.ShaderCompilationFailed;
    }

    return shader;
}

pub fn glErrStr(err: c_uint) []const u8 {
    return switch(err) {
        c.GL_INVALID_ENUM => "GL_INVALID_ENUM",
        c.GL_INVALID_VALUE => "GL_INVALID_VALUE",
        c.GL_INVALID_OPERATION => "GL_INVALID_OPERATION",
        c.GL_INVALID_FRAMEBUFFER_OPERATION => "GL_INVALID_FRAMEBUFFER_OPERATION",
        c.GL_OUT_OF_MEMORY => "GL_OUT_OF_MEMORY",
        c.GL_STACK_UNDERFLOW => "GL_STACK_UNDERFLOW",
        c.GL_STACK_OVERFLOW => "GL_STACK_OVERFLOW",
        else => "Unknown Error",
    };
}

pub fn glCheckError() !void {
    const err = c.glGetError();
    if(err == c.GL_NO_ERROR) return;
    log.err("Got gl error: {d}/{s}", .{err, glErrStr(err)});
    return error.GL_Error;
}

pub fn gewrap(return_value: anytype) !@TypeOf(return_value) {
    try glCheckError();
    return return_value;
}