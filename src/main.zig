const std = @import("std");
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const render = @import("render.zig"); // rend
const plat = @import("platform.zig");
const c = sdl.c;
const log = std.log.scoped(.main);
const math = @import("math.zig");
const shared = @import("shared.zig");

const x = math.x;
const y = math.y;
const z = math.z;

// https://www.khronos.org/opengl/wiki/Buffer_Texture

var global_allocator: ?std.mem.Allocator = null;
pub fn allocator() std.mem.Allocator {
    return global_allocator.?;
}

// todo generate this based on @import("root")
const State = struct {
    pub fn create(launcher_data: *const shared.LauncherData) !*State {
        const page_alloc = std.heap.page_allocator;
        const global_state = try page_alloc.create(State);
        errdefer page_alloc.destroy(global_state);
        try init(launcher_data, global_state);
        return global_state;
    }
    pub fn destroy(state: *State) void {
        deinit(state);
        const page_alloc = std.heap.page_allocator;
        page_alloc.destroy(state);
    }

    gpa: std.heap.GeneralPurposeAllocator(.{}),
    launcher_data: *const shared.LauncherData,
    platform: plat.Platform,
    world: game.World,
    renderer: render.Renderer,
    fullscreen: bool,
};

fn extern_init(launcher_data: *const shared.LauncherData) callconv(.C) usize {
    const res = State.create(launcher_data) catch @panic("todo pass through errors");
    return @ptrToInt(res);
}
fn extern_deinit(data: usize) callconv(.C) void {
    const state = @intToPtr(*State, data);
    state.destroy();
}
fn extern_onEvent(data: usize, event: *const c.SDL_Event) callconv(.C) void {
    const state = @intToPtr(*State, data);
    onEvent(state, event.*) catch @panic("todo pass through errors");
}
fn extern_onRender(data: usize) callconv(.C) void {
    const state = @intToPtr(*State, data);
    onRender(state) catch @panic("todo pass through errors");
}
fn extern_initReplace(data: usize) callconv(.C) void {
    const state = @intToPtr(*State, data);
    initReplace(state);
}

export fn pg_get_app() callconv(.C) shared.App {
    return .{
        .init = &extern_init,
        .deinit = &extern_deinit,
        .onEvent = &extern_onEvent,
        .onRender = &extern_onRender,
        .initReplace = &extern_initReplace,
    };
}

fn initReplace(state: *State) void {
    global_allocator = state.gpa.allocator();
}

fn init(launcher_data: *const shared.LauncherData, state: *State) !void {
    state.* = .{
        .gpa = undefined,
        .launcher_data = undefined,
        .platform = undefined,
        .world = undefined,
        .renderer = undefined,
        .fullscreen = undefined,
    };

    state.gpa = std.heap.GeneralPurposeAllocator(.{}){};
    global_allocator = state.gpa.allocator();

    state.launcher_data = launcher_data;

    state.platform = try plat.Platform.init(launcher_data.window);

    state.world = try game.World.init();
    errdefer state.world.deinit();

    const t_lab = game.Tile{.id = .lab_tile};
    const t_block = game.Tile{.id = .block};
    const t_conveyor_w = game.Tile{.id = .conveyor, .data_1 = 0};
    const t_conveyor_a = game.Tile{.id = .conveyor, .data_1 = 1};
    const t_conveyor_d = game.Tile{.id = .conveyor, .data_1 = 2};
    const t_conveyor_s = game.Tile{.id = .conveyor, .data_1 = 3};
    const t_spawner_d = game.Tile{.id = .spawner, .data_1 = 2};
    const t_air = game.Tile{.id = .air};
    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,
            t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab, t_lab,

            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_conveyor_a, t_conveyor_a, t_conveyor_a, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_air, t_air, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_air, t_air, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_air, t_air, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_d, t_conveyor_d, t_conveyor_d, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_spawner_d, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_lab,

            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_lab,
        });
        const newproduct = game.Product{
            .id = state.world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = math.Vec3i{5, 5, -1},
            .size = math.Vec3i{10, 10, 3},
            .fixed = true,
        };
        try state.world.products.append(newproduct);
    }
    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            t_air, t_air, t_air, t_air, t_block,
            t_air, t_air, t_block, t_block, t_block,
            t_air, t_air, t_block, t_block, t_air,
            t_air, t_air, t_block, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air,

            t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_block, t_air,
            t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air,
        });
        const newproduct = game.Product{
            .id = state.world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = math.Vec3i{6, 7, 2},
            .size = math.Vec3i{5, 5, 2},
        };
        try state.world.products.append(newproduct);
    }
    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            t_block, t_block,

            t_block, t_air,
            t_block, t_air,
            t_block, t_air,
        });
        const newproduct = game.Product{
            .id = state.world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = math.Vec3i{9, 6, 0},
            .size = math.Vec3i{2, 1, 4},
        };
        try state.world.products.append(newproduct);
    }

    // we should seperate View from Renderer
    // - Game is the game state
    // - View views the game state for the current client
    // - Render renders the game in the current view
    // or something
    state.renderer = try render.Renderer.init(&state.platform, &state.world);

    state.fullscreen = false;
}
fn deinit(state: *State) void {
    state.world.deinit();
    if(state.gpa.deinit()) @panic("memory leak");
}

fn onEvent(state: *State, event: c.SDL_Event) !void {
    state.platform.updateWithEvent(event);
    if(event.type == c.SDL_MOUSEBUTTONDOWN) {
        if(!state.platform.mouse_captured) {
            try state.platform.startCaptureMouse();
        }else{
            const under_cursor = state.renderer.screenToWorld(math.Vec2f{0.0, 0.0}, 0.0);
            const blockpos = math.ecast(i32, @floor(under_cursor));
            try state.world.placeTile(blockpos, .{.id = .block});
            // note: for deletion, we'll have an air block you place
            // note: todo seperate 'view' and 'render'
            // - 'view' contains information about the player and stuff
            //   - ie: position, camera zoom, selected object, …
            // - 'render' renders the view
            // - these are pretty tightly coupled but not identical
            // note: placeblock isn't this simple
            // if there are multiple possible things this block could be attached to,
            // you'll be asked to select one first or something.
            // we probably won't just merge them all together.
            // todo: highlight the currently selected group of objects
        }
    }else if(event.type == c.SDL_MOUSEMOTION and state.platform.mouse_captured) {
        const mod_state = c.SDL_GetModState();
        const shift_down = (mod_state & c.KMOD_LSHIFT != 0) or (mod_state & c.KMOD_RSHIFT != 0);
        // we want to move based on the current scale
        const minsz = @intToFloat(f64, std.math.min(state.platform.window_size[x], state.platform.window_size[y]));
        const vec = math.Vec2f{
            @intToFloat(f64, event.motion.xrel) / minsz * 2 / state.renderer.camera_scale(),
            @intToFloat(f64, event.motion.yrel) / minsz * 2 / state.renderer.camera_scale(),
        };
        if(shift_down) {
            state.renderer.camera_pos[math.z] -= vec[math.y] / render.tile_height * render.tile_height;
            // "/ 0.2" if you want it to be 1:1 mouse pixel to screen pixel
            // excluding that, it is 1:5 mouse pixel to screen pixel
            log.info("cam height: {d}", .{state.renderer.camera_pos[math.z]});
        }else{
            state.renderer.camera_pos += math.join(f64, .{vec, 0.0});
        }
    }else if(event.type == c.SDL_KEYDOWN) {
        switch(event.key.keysym.sym) {
            c.SDLK_ESCAPE => {
                try state.platform.stopCaptureMouse();
            },
            'q' => {
                log.info("q pressed!", .{});
            },
            'f' => {
                state.fullscreen =! state.fullscreen;
                state.platform.setFullscreen(state.fullscreen) catch {
                    state.fullscreen =! state.fullscreen;
                };
            },
            'r' => {
                const mod_state = c.SDL_GetModState();
                const shift_down = (mod_state & c.KMOD_LSHIFT != 0) or (mod_state & c.KMOD_RSHIFT != 0);
                if(shift_down) {
                    state.launcher_data.reload();
                }else {
                    state.renderer.recompileShaders() catch |e| {
                        log.err("Failed to recompile shaders: {}", .{e});
                    };
                }
            },
            c.SDLK_RIGHT => {
                state.world.physicsStep();
                log.info("Step", .{});
            },
            else => {},
        }
    }else if(event.type == c.SDL_MOUSEWHEEL) {
        state.renderer.camera_scale_factor += event.wheel.preciseY;
        // ^ why is it backwards on mac?
        // max zoom in: 22
        // max zoom out: -13
        if(state.renderer.camera_scale_factor > 22) state.renderer.camera_scale_factor = 22;
        if(state.renderer.camera_scale_factor < -13) state.renderer.camera_scale_factor = -13;
        std.log.info("mwheel {d}", .{state.renderer.camera_scale_factor});
    }
    // if(event.type == c.SDL_MULTIGESTURE) {
    //     // rotation: dTheta, zoom: dDist
    //     // it doesn't include scroll

    //     // weird, it gives physical location on the trackpad normalized from 0 to 1
    //     log.info("zoom {d} {d} {d} {d}", .{event.mgesture.dDist, event.mgesture.dDist, event.mgesture.x, event.mgesture.y});
    // }
}
fn onRender(state: *State) !void {
    const curr_timestamp = std.time.milliTimestamp();

    if(global_allocator == null) {
        return error.NoGlobalAllocator;
    }

    try state.renderer.renderFrame(@intToFloat(f64, curr_timestamp));

    state.platform.present();
}
