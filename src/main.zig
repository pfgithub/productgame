const std = @import("std");
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const render = @import("render.zig");
const plat = @import("platform.zig");
const c = sdl.c;
const log = std.log.scoped(.main);
const math = @import("math.zig");

const x = math.x;
const y = math.y;
const z = math.z;

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

    var platform = try plat.Platform.init();

    var world = try game.World.init();
    defer world.deinit();

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
            .id = world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = math.Vec3i{5, 5, -1},
            .size = math.Vec3i{10, 10, 3},
            .fixed = true,
        };
        try world.products.append(newproduct);
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
            .id = world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = math.Vec3i{6, 7, 2},
            .size = math.Vec3i{5, 5, 2},
        };
        try world.products.append(newproduct);
    }
    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            t_block, t_block,

            t_block, t_air,
            t_block, t_air,
            t_block, t_air,
        });
        const newproduct = game.Product{
            .id = world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = math.Vec3i{9, 6, 0},
            .size = math.Vec3i{2, 1, 4},
        };
        try world.products.append(newproduct);
    }

    // we should seperate View from Renderer
    // - Game is the game state
    // - View views the game state for the current client
    // - Render renders the game in the current view
    // or something
    var renderer = try render.Renderer.init(&platform, &world);

    var fullscreen = false;

    var prev_timestamp = @intToFloat(f64, std.time.milliTimestamp());

    app: while(true) {
        try sdl.glCheckError();
        const curr_timestamp = @intToFloat(f64, std.time.milliTimestamp());
        defer prev_timestamp = curr_timestamp;
        // log.info("mspf: {d}", .{ms_timestamp - prev_timestamp});

        while(platform.pollEvent()) |event| {
            if(event.type == c.SDL_MOUSEBUTTONDOWN) {
                try platform.startCaptureMouse();
            }else if(event.type == c.SDL_MOUSEMOTION and platform.mouse_captured) {
                const minsz = @intToFloat(f64, std.math.min(platform.window_size[x], platform.window_size[y]));
                renderer.camera_pos += math.Vec2f{
                    -@intToFloat(f64, event.motion.xrel) / minsz,
                    @intToFloat(f64, event.motion.yrel) / minsz,
                };
            }else if(event.type == c.SDL_KEYDOWN) {
                switch(event.key.keysym.sym) {
                    c.SDLK_ESCAPE => {
                        try platform.stopCaptureMouse();
                    },
                    'f' => {
                        fullscreen =! fullscreen;
                        platform.setFullscreen(fullscreen) catch {
                            fullscreen =! fullscreen;
                        };
                    },
                    'r' => {
                        renderer.recompileShaders() catch |e| {
                            log.err("Failed to recompile shaders: {}", .{e});
                        };
                    },
                    c.SDLK_RIGHT => {
                        world.physicsStep();
                        std.log.info("Step", .{});
                    },
                    else => {},
                }
            }else if(event.type == c.SDL_QUIT) {
                break :app;
            }else if(event.type == c.SDL_MOUSEWHEEL) {
                const prev_scale = renderer.camera_scale();
                renderer.camera_scale_factor -= event.wheel.preciseY;
                // max zoom in: 22
                // max zoom out: -13
                if(renderer.camera_scale_factor > 22) renderer.camera_scale_factor = 22;
                if(renderer.camera_scale_factor < -13) renderer.camera_scale_factor = -13;
                const next_scale = renderer.camera_scale();
                renderer.camera_pos *= @splat(2, next_scale / prev_scale);
                std.log.info("mwheel {d}", .{renderer.camera_scale_factor});
            }
            // if(event.type == c.SDL_MULTIGESTURE) {
            //     // rotation: dTheta, zoom: dDist
            //     // it doesn't include scroll

            //     // weird, it gives physical location on the trackpad normalized from 0 to 1
            //     std.log.info("zoom {d} {d} {d} {d}", .{event.mgesture.dDist, event.mgesture.dDist, event.mgesture.x, event.mgesture.y});
            // }
        }

        try renderer.renderFrame(curr_timestamp);

        platform.present();
    }
}
