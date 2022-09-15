#line 2 "tile.frag"
#ifdef VERTEX_SHADER

flat out int v_tile_data_ptr;
out vec3 v_tile_position;
out vec3 v_qposition;
out float v_z;
void main() {
    gl_Position = vec4( i_position, 1.0 );
    v_tile_data_ptr = int(i_tile_data_ptr);
    v_tile_position = i_tile_position;
    v_z = -i_position.z * 100.0;
    v_qposition = i_position;
}

#endif
#ifdef FRAGMENT_SHADER

flat in int v_tile_data_ptr;
in vec3 v_tile_position;
in vec3 v_qposition;
in float v_z;
uniform usamplerBuffer u_tbo_tex;
out vec4 o_color;
uvec4 getMem(int ptr) {
    return texelFetch(u_tbo_tex, ptr);
}
uvec4 getTile(int ptr, ivec3 pos, ivec3 size) {
    if(any(greaterThanEqual(pos, size)) || any(lessThan(pos, ivec3(0, 0, 0)))) {
       return uvec4(0, 0, 0, 0); // out of bounds; return air tile
    }
    return getMem(ptr + 1 + pos.x + (pos.y * size.x) + (pos.z * size.x * size.y));
}

vec4 drawTile(uvec4 surrounding[9], vec2 position) {
    uvec4 tile = surrounding[4];

    if(tile.x == TILE_air) discard;
    if(tile.x == TILE_block) {
        // ok what I actually want is:
        // - imagine an inset rounded rectangle
        // - blur it
        // but it's not just a rounded rectangle
        // - it connects to nearby tiles. so if the bottom tile is a block, it uses that
        // https://raphlinus.github.io/graphics/2020/04/21/blurred-rounded-rects.html
        float vlen = length(position);
        vec4 edge_color = vec4(0.6, 0.6, 0.6, 1.0);
        if(surrounding[1].x == TILE_air) {
            if(position.y < -0.9) return edge_color;
        }
        if(surrounding[3].x == TILE_air) {
            if(position.x < -0.9) return edge_color;
        }
        if(surrounding[5].x == TILE_air) {
            if(position.x > 0.9) return edge_color;
        }
        if(surrounding[7].x == TILE_air) {
            if(position.y > 0.9) return edge_color;
        }
        float dist = 1 - (vlen* 0.2) ;
        return vec4(dist, dist, dist, 1.0);
    }
    if(tile.x == TILE_conveyor) return vec4(0.0, 1.0, 0.0, 1.0);
    if(tile.x == TILE_spawner) return vec4(0.0, 0.0, 1.0, 1.0);
    return vec4(0.0, 1.0, 1.0, 1.0);
}

void main() {
    uvec4 header = getMem(v_tile_data_ptr);
    ivec3 size = ivec3(header.xyz);
    ivec3 pos = ivec3(floor(v_tile_position));
    uvec4 surrounding[9] = uvec4[9](
        getTile(v_tile_data_ptr, pos + ivec3(-1, -1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(0, -1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(1, -1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(-1, 0, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(0, 0, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(1, 0, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(-1, 1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(0, 1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(1, 1, 0), size)
    );
    o_color = drawTile(surrounding, (mod(v_tile_position.xy, 1.0)) * 2.0 - 1.0);
    if(v_z <= 0.1 && v_z >= -0.1) o_color *= vec4(0.9, 0.9, 0.9, 1.0);
}

#endif