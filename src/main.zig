const std = @import("std");
const sdl = @import("sdl.zig");
const game = @import("game.zig");
const render = @import("render.zig");
const plat = @import("platform.zig");
const c = sdl.c;
const log = std.log.scoped(.main);

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
        });
        const newproduct = game.Product{
            .id = world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = game.Vec3{5, 5, -1},
            .size = game.Vec3{10, 10, 1},
            .fixed = true,
        };
        try world.products.append(newproduct);
    }
    {
        const newproduct_tiles = try allocator().dupe(game.Tile, &[_]game.Tile{
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_conveyor_a, t_conveyor_a, t_conveyor_a, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_air, t_air, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_air, t_air, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_s, t_air, t_air, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_conveyor_d, t_conveyor_d, t_conveyor_d, t_conveyor_w, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
            t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air, t_air,
        });
        const newproduct = game.Product{
            .id = world.nextProductId(),
            // MxN array of tiles
            .tiles = newproduct_tiles,
            .tiles_updated = 1,
            .pos = game.Vec3{5, 5, 0},
            .size = game.Vec3{10, 10, 1},
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
            .pos = game.Vec3{6, 7, 2},
            .size = game.Vec3{5, 5, 2},
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
            .pos = game.Vec3{9, 6, 0},
            .size = game.Vec3{2, 1, 4},
        };
        try world.products.append(newproduct);
    }

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
                const minsz = @intToFloat(f32, std.math.min(platform.window_size[game.x], platform.window_size[game.y]));
                renderer.camera_pos += game.Vec2f{
                    -@intToFloat(f32, event.motion.xrel) / minsz,
                    @intToFloat(f32, event.motion.yrel) / minsz,
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
                if(event.wheel.preciseY > 0) {
                    renderer.camera_scale *= 2.0;
                    renderer.camera_pos *= @splat(2, @as(f32, 2.0));
                }else{
                    renderer.camera_scale /= 2.0;
                    renderer.camera_pos /= @splat(2, @as(f32, 2.0));
                }
                std.log.info("mwheel {d} {d}", .{event.wheel.preciseX, event.wheel.preciseY});
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
