// ZapZap Game Renderer — WGSL Shaders
// Reads per-instance data from a storage buffer (SharedArrayBuffer-backed).
// Two fragment entry points: standard alpha blend and additive HDR glow.

// ---- Uniforms ----

struct Camera {
    projection: mat4x4<f32>,
};
@group(0) @binding(0) var<uniform> camera: Camera;

// ---- Textures ----

@group(1) @binding(0) var t_atlas: texture_2d<f32>;
@group(1) @binding(1) var s_atlas: sampler;

// ---- Instance data from storage buffer ----
// Matches RenderInstance layout: 8 floats = 32 bytes per instance.
// [x, y, rotation, scale, sprite_id, alpha, flags, pad]

struct Instance {
    position: vec2<f32>,
    rotation: f32,
    scale: f32,
    sprite_id: f32,
    alpha: f32,
    flags: f32,
    atlas_row: f32,
};

@group(2) @binding(0) var<storage, read> instances: array<Instance>;

// ---- Vertex I/O ----

struct VertexInput {
    @builtin(vertex_index) vertex_index: u32,
    @builtin(instance_index) instance_index: u32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) tex_coord: vec2<f32>,
    @location(1) alpha: f32,
};

// Unit quad vertices (2 triangles)
// Positions: (-0.5,-0.5), (0.5,-0.5), (-0.5,0.5), (0.5,0.5)
// UVs:       (0, 1),      (1, 1),     (0, 0),     (1, 0)
const QUAD_POS = array<vec2<f32>, 4>(
    vec2(-0.5, -0.5),
    vec2( 0.5, -0.5),
    vec2(-0.5,  0.5),
    vec2( 0.5,  0.5),
);
const QUAD_UV = array<vec2<f32>, 4>(
    vec2(0.0, 1.0),
    vec2(1.0, 1.0),
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
);
const QUAD_IDX = array<u32, 6>(0u, 1u, 2u, 2u, 1u, 3u);

// Texture atlas layout: 16 columns × 8 rows (base_tiles.png)
const ATLAS_COLS: f32 = 16.0;
const ATLAS_ROWS: f32 = 8.0;

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    let inst = instances[input.instance_index];
    let tri_idx = QUAD_IDX[input.vertex_index];
    let pos = QUAD_POS[tri_idx];
    let uv = QUAD_UV[tri_idx];

    // Tile size in world units
    let tile_size = 50.0 * inst.scale;

    // Apply rotation
    let cos_r = cos(inst.rotation);
    let sin_r = sin(inst.rotation);
    let rotated = vec2<f32>(
        pos.x * cos_r - pos.y * sin_r,
        pos.x * sin_r + pos.y * cos_r,
    );

    // Scale and translate to world position
    let world_pos = rotated * tile_size + inst.position;
    out.clip_position = camera.projection * vec4<f32>(world_pos, 0.0, 1.0);

    // Map sprite_id to atlas UV.
    // sprite_id = atlas column (after GRID_CODEP lookup in Rust).
    // atlas_row = row in the 16x8 atlas (1.0 = normal tiles, 3.0 = pins).
    let col = inst.sprite_id % ATLAS_COLS;
    let row = inst.atlas_row;

    let uv_origin = vec2<f32>(col / ATLAS_COLS, row / ATLAS_ROWS);
    let uv_size = vec2<f32>(1.0 / ATLAS_COLS, 1.0 / ATLAS_ROWS);
    out.tex_coord = uv_origin + uv * uv_size;

    out.alpha = inst.alpha;

    return out;
}

// Standard alpha-blended fragment shader
@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let color = textureSample(t_atlas, s_atlas, in.tex_coord);
    return color * in.alpha;
}

// ---- Effects vertex shader (raw triangle list, non-instanced) ----
// Vertex format: 5 floats per vertex (x, y, z, u, v)

struct EffectsVertexInput {
    @location(0) position: vec3<f32>,
    @location(1) tex_coord: vec2<f32>,
};

@vertex
fn vs_effects(input: EffectsVertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.clip_position = camera.projection * vec4<f32>(input.position.xy, 0.0, 1.0);
    out.tex_coord = input.tex_coord;
    out.alpha = 1.0;
    return out;
}

// Additive fragment shader for HDR glow effects (electric arcs).
// Multiplies by 6.4 to push into EDR range on supported displays.
@fragment
fn fs_additive(in: VertexOutput) -> @location(0) vec4<f32> {
    let color = textureSample(t_atlas, s_atlas, in.tex_coord);
    return color * 6.4 * in.alpha;
}
