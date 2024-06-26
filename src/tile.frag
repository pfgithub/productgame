#line 2 6000
#ifdef VERTEX_SHADER

flat out int v_tile_data_ptr;
out vec3 v_tile_position;
out vec3 v_qposition;
void main() {
    gl_Position = vec4( i_position, 1.0 );
    v_tile_data_ptr = int(i_tile_data_ptr);
    v_tile_position = i_tile_position;
    v_qposition = i_position;
}

#endif
#ifdef FRAGMENT_SHADER

flat in int v_tile_data_ptr;
in vec3 v_tile_position;
in vec3 v_qposition;
uniform usamplerBuffer u_tbo_tex;
out vec4 o_color;
uvec4 getMem(int ptr) {
    return texelFetch(u_tbo_tex, ptr);
}
uvec4 getTile(int ptr, ivec3 pos, ivec3 size) {
    if(any(greaterThanEqual(pos, size)) || any(lessThan(pos, ivec3(0, 0, 0)))) {
       return uvec4(0, 0, 0, 0); // out of bounds; return air tile
    }
    return getMem(ptr + 3 + pos.x + (pos.y * size.x) + (pos.z * size.x * size.y));
}

float map(float value, float min1, float max1, float min2, float max2) {
  return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

vec4 drawTile2(float progress, uvec4 surrounding[9], vec2 position) {
    uvec4 tile = surrounding[4];

    // TODO: just read a texture from a texture map instead of whatever this is
    if(tile.x == TILE_lab_tile || tile.x == TILE_block) {
        float x = position.x;
        float y = position.y;

        float xmax = (4 * x * (1 - x));
        float xmin = (xmax / 3.0) + (2.0 / 3.0);

        float ymax = (4 * y * (1 - y));
        float ymin = (ymax / 3.0) + (2.0 / 3.0);

        vec3 color = vec3(1.0, 1.0, 1.0);
        color *= map(pow(xmin * ymin, 1.0/8.0), 0.0, 1.0, 0.0, 1.0);
        if(tile.x == TILE_block) color *= vec3(0.8);
        return vec4(color, 1.0);
    }
    if(tile.x == TILE_conveyor) {
        float axis = 0;
        float cross_axis = 0;
        if(tile.y == 0u) {
            axis = position.y;
            cross_axis = 1-position.x;
        }else if(tile.y == 1u) {
            axis = position.x;
            cross_axis = position.y;
        }else if(tile.y == 2u) {
            axis =1-position.x;
            cross_axis = 1-position.y;
        }else if(tile.y == 3u) {
            axis = 1-position.y;
            cross_axis = position.x;
        }
        return vec4(mod(axis + progress, 1.0), cross_axis, 0.0, 1.0);
    }
    if(tile.x == TILE_spawner) return vec4(0.0, 0.0, 1.0, 1.0);
    return vec4(0.0, 1.0, 1.0, 1.0);
}
vec4 drawTile(float progress, uvec4 surrounding[9], vec2 position) {
    uvec4 tile = surrounding[4];

    if(tile.x == TILE_air) return vec4(0.0, 0.0, 0.0, 0.0);

    float x = position.x;
    float y = position.y;

    float xmax = (4 * x * (1 - x));
    float xpb = xmax;

    float ymax = (4 * y * (1 - y));
    float ypb = ymax;

    if(surrounding[1].x != TILE_air) {
        if(y < 0.5) ypb = 1.0;
    }
    if(surrounding[3].x != TILE_air) {
        if(x < 0.5) xpb = 1.0;
    }
    if(surrounding[5].x != TILE_air) {
        if(x > 0.5) xpb = 1.0;
    }
    if(surrounding[7].x != TILE_air) {
        if(y > 0.5) ypb = 1.0;
    }
    if(surrounding[0].x == TILE_air && surrounding[1].x != TILE_air && surrounding[3].x != TILE_air) {
        if(x < 0.5 && y < 0.5) {
            xpb = max(xmax, ymax);
            ypb = 1.0;
        }
    }
    if(surrounding[2].x == TILE_air && surrounding[1].x != TILE_air && surrounding[5].x != TILE_air) {
        if(x > 0.5 && y < 0.5) {
            xpb = max(xmax, ymax);
            ypb = 1.0;
        }
    }
    if(surrounding[6].x == TILE_air && surrounding[7].x != TILE_air && surrounding[3].x != TILE_air) {
        if(x < 0.5 && y > 0.5) {
            xpb = max(xmax, ymax);
            ypb = 1.0;
        }
    }
    if(surrounding[8].x == TILE_air && surrounding[7].x != TILE_air && surrounding[5].x != TILE_air) {
        if(x > 0.5 && y > 0.5) {
            xpb = max(xmax, ymax);
            ypb = 1.0;
        }
    }

    // consider:
    // making xmin/ymin = 0.0 and that's the texture's job
    
    vec4 color = drawTile2(progress, surrounding, position);
    vec3 q = color.xyz;
    q *= map(pow(xpb * ypb, 1.0/8.0), 0.0, 1.0, 0.0, 1.0);
    color = vec4(q, color.a);
    return vec4(color);
}

uvec4[9] getSurrounding(ivec3 center, ivec3 size) {
    return uvec4[9](
        getTile(v_tile_data_ptr, center + ivec3(-1, -1, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(0, -1, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(1, -1, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(-1, 0, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(0, 0, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(1, 0, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(-1, 1, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(0, 1, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(1, 1, 0), size)
    );
}
uvec4[9] getVerticalSurrounding(ivec3 center, ivec3 size) {
    return uvec4[9](
        getTile(v_tile_data_ptr, center + ivec3(-1, 0, 1), size),
        getTile(v_tile_data_ptr, center + ivec3(0, 0, 1), size),
        getTile(v_tile_data_ptr, center + ivec3(1, 0, 1), size),
        getTile(v_tile_data_ptr, center + ivec3(-1, 0, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(0, 0, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(1, 0, 0), size),
        getTile(v_tile_data_ptr, center + ivec3(-1, 0, -1), size),
        getTile(v_tile_data_ptr, center + ivec3(0, 0, -1), size),
        getTile(v_tile_data_ptr, center + ivec3(1, 0, -1), size)
    );
}

vec4 blend(vec4 a, vec4 b) {
    return (a * a.a) + (b * (1 - a.a));
}

int uvec4ToInt(uvec4 a) {
    // TODO: support negatives
    return (int(a.x) << 24) + (int(a.y) << 16) + (int(a.z) << 8) + int(a.a);
}

vec4 ui(vec2 pos) {
    if(distance(vec2(0, 0), pos) <= 0.01) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    return vec4(0.0, 0.0, 0.0, 0.0);
}

bvec2 and2(bvec2 a, bvec2 b) {
    return bvec2(a.x && b.x, a.y && b.y);
}

void main() {
    if(v_tile_data_ptr == 0) {
        o_color = ui(v_tile_position.xy);
    }else if(v_tile_data_ptr == 1) {
        vec2 sub_pos = (v_tile_position.xy + vec2(0, -v_tile_position.z * CONST_height)) * 2.0 - 1.0;
        vec2 qpos = v_tile_position.xy * 2.0 - 1.0;
        vec2 qpos_b = (v_tile_position.xy + vec2(0, -CONST_height)) * 2.0 - 1.0;
        o_color = vec4(0.0, 0.0, 0.0, 0.0);
        if(all(lessThanEqual(abs(qpos_b), vec2(1.0)))
            && any(and2(greaterThanEqual(abs(qpos_b), vec2(0.8)), greaterThanEqual(abs(qpos_b), vec2(0.5)).yx))
        ) {
            o_color = vec4(0.2, 0.2, 0.2, 1.0);
        }
        if(all(lessThanEqual(abs(sub_pos), vec2(1.0)))
            // && any(lessThanEqual(abs(sub_pos), vec2(0.05)))
            && (
                // small problem: our opengl coordinates aren't even on xy
                // any(lessThanEqual(abs(v_qposition.xy), vec2(0.01)))
                any(greaterThanEqual(abs(sub_pos), vec2(0.95)))
            )
        ) {
            o_color = vec4(0.0, 0.0, 1.0, 1.0);
        }
        if(all(lessThanEqual(abs(qpos), vec2(1.0)))
            && any(and2(greaterThanEqual(abs(qpos), vec2(0.8)), greaterThanEqual(abs(qpos), vec2(0.5)).yx))
        ) {
            o_color = vec4(0.0, 0.0, 0.0, 1.0);
        }
        // float xpb = (4 * x * (1 - x));
        // float ypb = (4 * y * (1 - y));
        // float val = map(pow(xpb * ypb, 1.0/8.0), 0.0, 1.0, 0.0, 1.0);
        // o_color = blend(vec4(0.0, 0.0, 1.0, val), o_color);
    }else{
        float progress = float(getMem(1).r) / 255.0;
        vec2 tilepos = mod(v_tile_position.xy, 1.0);
        ivec3 size = ivec3(
            uvec4ToInt(getMem(v_tile_data_ptr + 0)),
            uvec4ToInt(getMem(v_tile_data_ptr + 1)),
            uvec4ToInt(getMem(v_tile_data_ptr + 2))
        );
        ivec3 pos = ivec3(floor(v_tile_position));
        uvec4 surrounding[9] = getSurrounding(pos, size);
        o_color = drawTile(progress, surrounding, tilepos);
        // TODO vv move this to a different quad
        if(o_color.a < 0.99 && tilepos.y < CONST_height) {
            uvec4 surrounding2[9] = getVerticalSurrounding(pos + ivec3(0, -1, 0), size);
            vec4 ncol = drawTile(progress, surrounding2, vec2(tilepos.x, tilepos.y / CONST_height));
            o_color = blend(o_color, vec4(ncol.xyz * 0.3, ncol.a));
        }
    }
    if(o_color.a < 0.99) {
        discard;
    }
}

#endif