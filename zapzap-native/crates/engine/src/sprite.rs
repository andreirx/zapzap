use bytemuck::{Pod, Zeroable};
use crate::assets::TextureHandle;

/// Per-instance sprite data sent to the GPU.
/// Layout: [x, y, u, v, w, h] — position, texture UV origin, and sprite size.
#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct SpriteInstance {
    /// World-space position (center of the sprite).
    pub position: [f32; 2],
    /// Top-left UV coordinate in the texture atlas.
    pub uv: [f32; 2],
    /// Size of the UV region in the atlas (width, height in UV space).
    pub uv_size: [f32; 2],
    /// World-space size of the sprite (width, height in pixels/units).
    pub size: [f32; 2],
    /// Rotation in radians (counter-clockwise).
    pub rotation: f32,
    /// Alpha / opacity (0.0 = invisible, 1.0 = opaque).
    pub alpha: f32,
}

impl SpriteInstance {
    pub fn new(x: f32, y: f32, u: f32, v: f32, uv_w: f32, uv_h: f32, w: f32, h: f32) -> Self {
        Self {
            position: [x, y],
            uv: [u, v],
            uv_size: [uv_w, uv_h],
            size: [w, h],
            rotation: 0.0,
            alpha: 1.0,
        }
    }

    pub fn with_rotation(mut self, radians: f32) -> Self {
        self.rotation = radians;
        self
    }

    pub fn with_alpha(mut self, alpha: f32) -> Self {
        self.alpha = alpha;
        self
    }
}

/// A batch of sprites sharing the same texture atlas.
pub struct SpriteBatch {
    pub texture: TextureHandle,
    pub instances: Vec<SpriteInstance>,
    pub blend_mode: BlendMode,
}

impl SpriteBatch {
    pub fn new(texture: TextureHandle) -> Self {
        Self {
            texture,
            instances: Vec::new(),
            blend_mode: BlendMode::Alpha,
        }
    }

    pub fn with_blend_mode(mut self, mode: BlendMode) -> Self {
        self.blend_mode = mode;
        self
    }

    pub fn push(&mut self, sprite: SpriteInstance) {
        self.instances.push(sprite);
    }

    pub fn clear(&mut self) {
        self.instances.clear();
    }
}

/// Blend mode for a rendering layer / batch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BlendMode {
    /// Standard src-alpha, one-minus-src-alpha blending.
    Alpha,
    /// Additive blending (src=One, dst=One). Used for HDR glow effects.
    Additive,
}

/// Per-vertex data for the unit quad. The vertex shader generates actual
/// positions from instance data + this base quad.
#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct QuadVertex {
    /// Position in unit quad space: corners at (-0.5,-0.5) to (0.5,0.5).
    pub position: [f32; 2],
    /// UV coordinates (0,0) to (1,1) — remapped per-instance.
    pub uv: [f32; 2],
}

/// The 4 vertices of a unit quad, used for instanced sprite rendering.
pub const QUAD_VERTICES: [QuadVertex; 4] = [
    QuadVertex {
        position: [-0.5, -0.5],
        uv: [0.0, 1.0],
    },
    QuadVertex {
        position: [0.5, -0.5],
        uv: [1.0, 1.0],
    },
    QuadVertex {
        position: [0.5, 0.5],
        uv: [1.0, 0.0],
    },
    QuadVertex {
        position: [-0.5, 0.5],
        uv: [0.0, 0.0],
    },
];

/// Index buffer for the unit quad (2 triangles).
pub const QUAD_INDICES: [u16; 6] = [0, 1, 2, 2, 3, 0];
