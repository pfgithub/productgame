const std = @import("std");
pub const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdint.h");
    @cInclude("assert.h");
    @cDefine("GL_GLEXT_PROTOTYPES", "");
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_opengl.h");
});

pub fn sewrap(return_value: c_int) !void {
    if(return_value != 0) {
        std.log.err("SDL Error: {s}", .{std.mem.span(c.SDL_GetError())});
        return error.SDL_Error;
    }
}

pub fn createCompileShader(kind: c_uint, source: []const u8) !c_uint {
    const shader = try gewrap(c.glCreateShader(kind));
    try gewrap(c.glShaderSource(shader, 1, &source.ptr, &@intCast(c_int, source.len)));
    try gewrap(c.glCompileShader(shader));

    var status: c.GLint = undefined;
    try gewrap(c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status));
    if(status == c.GL_FALSE) {
        std.log.err("GL Error: Shader compilation failed", .{});
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
    std.log.err("Got gl error: {d}/{s}", .{err, glErrStr(err)});
    return error.GL_Error;
}

pub fn gewrap(return_value: anytype) !@TypeOf(return_value) {
    try glCheckError();
    return return_value;
}