const c = @import("sdl.zig").c;

pub const LauncherData = extern struct {
    // ie the refresh function
    window: *c.SDL_Window,
};
pub const App = extern struct {
    init: *const fn(launcher_data: *const LauncherData) callconv(.C) usize,
    deinit: *const fn(data: usize) callconv(.C) void,
    onEvent: *const fn(data: usize, event: *const c.SDL_Event) callconv(.C) void,
    onRender: *const fn(data: usize) callconv(.C) void,
    // setupGlobalState: *fn(data: *anyopaque) void,
};