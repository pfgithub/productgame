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
    //if(any(greaterThanEqual(pos, size)) || any(lessThan(pos, ivec3(0, 0, 0)))) {
    //    return uvec4(0, 0, 0, 0); // out of bounds; return air tile
    //}
    return getMem(ptr + 1 + pos.x + (pos.y * size.x) + (pos.z * size.x * size.y));
}

vec4 drawTile(uvec4 surrounding[9]) {
    uvec4 tile = surrounding[4];

    if(tile.x == 0u) discard;
    if(tile.x == TILE_block) return vec4(1.0f, 0.0, 0.0, 1.0);
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
        getTile(v_tile_data_ptr, pos + ivec3(-1, 0, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(-1, 1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(0, -1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(0, 0, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(0, 1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(1, -1, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(1, 0, 0), size),
        getTile(v_tile_data_ptr, pos + ivec3(1, 1, 0), size)
    );
    o_color = drawTile(surrounding);
    if(v_z <= 0.1 && v_z >= -0.1) o_color *= vec4(0.8, 0.8, 0.8, 1.0);
}

#endif