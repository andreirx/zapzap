use crate::components::{Direction, Marking};
use crate::systems::board::{GameBoard, Rng};

// ---- Segment Colors (UV mapping into arrows.png atlas) ----

/// 13 colors from the arrows texture atlas. Each has UV coords for first/middle/last segments.
/// UVs are normalized to [0,1] based on a 16x16 grid in the arrows texture.
/// The arrows atlas maps: columns 0-3, rows from 2-6 (in 16ths).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum SegmentColor {
    Red = 0,
    Orange,
    Yellow,
    LimeGreen,
    Green,
    GreenCyan,
    Cyan,
    SkyBlue,
    Blue,
    Indigo,
    Magenta,
    Pink,
    White,
}

impl SegmentColor {
    pub const ALL: [SegmentColor; 13] = [
        Self::Red, Self::Orange, Self::Yellow, Self::LimeGreen,
        Self::Green, Self::GreenCyan, Self::Cyan, Self::SkyBlue,
        Self::Blue, Self::Indigo, Self::Magenta, Self::Pink, Self::White,
    ];

    pub fn random(rng: &mut Rng) -> Self {
        Self::ALL[rng.next_int(13) as usize]
    }

    /// Returns (first, middle, last) UV pairs as ((u_start, v), (u_end, v)) for each segment type.
    /// Legacy uses `4.0*tu` offset (col offset of 4 in the arrows atlas which is 16 cols).
    /// tu = 1/16. Columns 0-3 map to the 4 segment color columns.
    pub fn uvs(&self) -> SegmentUVs {
        let tu: f32 = 1.0 / 16.0;
        let (col, row_block) = match self {
            Self::Red =>       (0, 5),
            Self::Orange =>    (1, 5),
            Self::Yellow =>    (2, 5),
            Self::LimeGreen => (3, 5),
            Self::Green =>     (0, 4),
            Self::GreenCyan => (1, 4),
            Self::Cyan =>      (2, 4),
            Self::SkyBlue =>   (3, 4),
            Self::Blue =>      (0, 3),
            Self::Indigo =>    (1, 3),
            Self::Magenta =>   (2, 3),
            Self::Pink =>      (3, 3),
            Self::White =>     (3, 2),
        };
        let u0 = col as f32 * tu;
        let u1 = (col + 1) as f32 * tu;
        let row = row_block as f32;
        SegmentUVs {
            first_u: (u0, u1),
            first_v: row * tu,
            mid_u: (u0, u1),
            mid_v: (row + 0.5) * tu,
            last_u: (u0, u1),
            last_v: (row + 1.0) * tu,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct SegmentUVs {
    pub first_u: (f32, f32),
    pub first_v: f32,
    pub mid_u: (f32, f32),
    pub mid_v: f32,
    pub last_u: (f32, f32),
    pub last_v: f32,
}

// ---- Electric Arc (midpoint displacement) ----

#[derive(Debug, Clone)]
pub struct ElectricArc {
    pub start: [f32; 2],
    pub end: [f32; 2],
    pub points: Vec<[f32; 2]>,
    displacements: Vec<f32>,
    num_segments: usize,
    max_displacement: f32,
}

impl ElectricArc {
    pub fn new(start: [f32; 2], end: [f32; 2], power_of_two: u32, rng: &mut Rng) -> Self {
        let num_segments = 1usize << power_of_two;
        let mut arc = ElectricArc {
            start,
            end,
            points: vec![[0.0; 2]; num_segments + 1],
            displacements: vec![0.0; num_segments.saturating_sub(1)],
            num_segments,
            max_displacement: 0.2,
        };
        arc.points[0] = start;
        arc.points[num_segments] = end;
        arc.generate_displacements(rng);
        arc.generate_points(0, num_segments);
        arc
    }

    fn generate_displacements(&mut self, rng: &mut Rng) {
        for d in self.displacements.iter_mut() {
            // Random in [-max, max]
            let r = (rng.next_int(10000) as f32 / 5000.0) - 1.0;
            *d = r * self.max_displacement;
        }
    }

    fn generate_points(&mut self, start_idx: usize, end_idx: usize) {
        if end_idx - start_idx <= 1 {
            return;
        }
        let mid_idx = (start_idx + end_idx) / 2;
        let sp = self.points[start_idx];
        let ep = self.points[end_idx];
        let mid = [(sp[0] + ep[0]) * 0.5, (sp[1] + ep[1]) * 0.5];

        let dx = ep[0] - sp[0];
        let dy = ep[1] - sp[1];
        let len = (dx * dx + dy * dy).sqrt().max(0.001);
        let perp = [-dy / len, dx / len];

        let disp_idx = mid_idx.saturating_sub(1);
        let disp = if disp_idx < self.displacements.len() {
            self.displacements[disp_idx]
        } else {
            0.0
        };
        let dist = (dx * dx + dy * dy).sqrt();
        self.points[mid_idx] = [
            mid[0] + perp[0] * disp * dist,
            mid[1] + perp[1] * disp * dist,
        ];

        self.generate_points(start_idx, mid_idx);
        self.generate_points(mid_idx, end_idx);
    }

    /// Jitter the arc displacements for a living-wire effect.
    pub fn twitch(&mut self, factor: f32, rng: &mut Rng) {
        for d in self.displacements.iter_mut() {
            let r = (rng.next_int(10000) as f32 / 5000.0) - 1.0;
            *d += factor * r;
            *d = d.clamp(-self.max_displacement, self.max_displacement);
        }
        self.points[0] = self.start;
        self.points[self.num_segments] = self.end;
        self.generate_points(0, self.num_segments);
    }
}

// ---- Triangle Strip Mesh Generation ----

/// Generate triangle strip vertices from a polyline.
/// Output: Vec of [x, y, z, u, v] floats (5 per vertex).
/// Uses triangle strip topology.
pub fn build_strip_vertices(
    points: &[[f32; 2]],
    width: f32,
    color: SegmentColor,
) -> Vec<f32> {
    if points.len() < 2 {
        return Vec::new();
    }

    let uvs = color.uvs();
    let n = points.len();
    // Total vertices: 2*(n+2) = start cap + n points + end cap, each with 2 verts
    let mut verts = Vec::with_capacity((n + 2) * 2 * 5);

    // Helper: direction + perpendicular
    let dir = |a: [f32; 2], b: [f32; 2]| -> ([f32; 2], [f32; 2]) {
        let dx = b[0] - a[0];
        let dy = b[1] - a[1];
        let len = (dx * dx + dy * dy).sqrt().max(0.001);
        let d = [dx / len, dy / len];
        let p = [-d[1], d[0]];
        (d, p)
    };

    // Encode color index in z-component for procedural coloring in shader
    let color_z = color as u8 as f32;

    // Push a vertex pair
    let push_pair = |verts: &mut Vec<f32>, center: [f32; 2], perp: [f32; 2], w: f32, u: (f32, f32), v: f32| {
        // Left vertex
        verts.extend_from_slice(&[
            center[0] + perp[0] * w,
            center[1] + perp[1] * w,
            color_z,
            u.0,
            v,
        ]);
        // Right vertex
        verts.extend_from_slice(&[
            center[0] - perp[0] * w,
            center[1] - perp[1] * w,
            color_z,
            u.1,
            v,
        ]);
    };

    // Start cap: extend backwards from first point
    let (d0, p0) = dir(points[0], points[1]);
    let start_cap = [points[0][0] - d0[0] * width, points[0][1] - d0[1] * width];
    push_pair(&mut verts, start_cap, p0, width, uvs.first_u, uvs.first_v);

    // First point
    push_pair(&mut verts, points[0], p0, width, uvs.mid_u, uvs.mid_v);

    // Middle points: average perpendiculars from neighboring segments
    for i in 1..n - 1 {
        let (_, p_prev) = dir(points[i - 1], points[i]);
        let (_, p_next) = dir(points[i], points[i + 1]);
        // Average perpendicular
        let avg = [p_prev[0] + p_next[0], p_prev[1] + p_next[1]];
        let avg_len = (avg[0] * avg[0] + avg[1] * avg[1]).sqrt().max(0.001);
        let perp = [avg[0] / avg_len, avg[1] / avg_len];
        push_pair(&mut verts, points[i], perp, width, uvs.mid_u, uvs.mid_v);
    }

    // Last point
    let (d_last, p_last) = dir(points[n - 2], points[n - 1]);
    push_pair(&mut verts, points[n - 1], p_last, width, uvs.mid_u, uvs.mid_v);

    // End cap: extend forwards from last point
    let end_cap = [points[n - 1][0] + d_last[0] * width, points[n - 1][1] + d_last[1] * width];
    push_pair(&mut verts, end_cap, p_last, width, uvs.last_u, uvs.last_v);

    verts
}

/// Convert triangle strip vertices to triangle list (for WebGPU compatibility).
/// Input: pairs of vertices in strip order. Output: triangle list.
pub fn strip_to_triangles(strip_verts: &[f32], floats_per_vert: usize) -> Vec<f32> {
    let num_verts = strip_verts.len() / floats_per_vert;
    if num_verts < 3 {
        return Vec::new();
    }
    let num_tris = num_verts - 2;
    let mut out = Vec::with_capacity(num_tris * 3 * floats_per_vert);
    for i in 0..num_tris {
        let (a, b, c) = if i % 2 == 0 {
            (i, i + 1, i + 2)
        } else {
            (i + 1, i, i + 2)
        };
        let base_a = a * floats_per_vert;
        let base_b = b * floats_per_vert;
        let base_c = c * floats_per_vert;
        out.extend_from_slice(&strip_verts[base_a..base_a + floats_per_vert]);
        out.extend_from_slice(&strip_verts[base_b..base_b + floats_per_vert]);
        out.extend_from_slice(&strip_verts[base_c..base_c + floats_per_vert]);
    }
    out
}

// ---- Particle ----

#[derive(Debug, Clone)]
pub struct Particle {
    pub position: [f32; 2],
    pub speed: [f32; 2],
    pub width: f32,
    pub color: SegmentColor,
    pub lifetime: f32,   // seconds remaining
}

impl Particle {
    const FRICTION: f32 = 0.02;
    const ATTRACT_STRENGTH: f32 = 0.3;
    const SPEED_FACTOR: f32 = 0.8;

    pub fn new(position: [f32; 2], speed: [f32; 2], width: f32, color: SegmentColor, lifetime: f32) -> Self {
        Particle { position, speed, width, color, lifetime }
    }

    /// Advance particle physics. Returns false when expired.
    pub fn tick(&mut self, attractor: [f32; 2], dt: f32) -> bool {
        self.lifetime -= dt;
        if self.lifetime <= 0.0 {
            return false;
        }

        // Direction to attractor
        let dx = attractor[0] - self.position[0];
        let dy = attractor[1] - self.position[1];
        let len = (dx * dx + dy * dy).sqrt().max(0.001);
        let to_attr = [dx / len, dy / len];

        // Apply forces
        self.speed[0] += to_attr[0] * Self::ATTRACT_STRENGTH;
        self.speed[1] += to_attr[1] * Self::ATTRACT_STRENGTH;
        self.speed[0] *= 1.0 - Self::FRICTION;
        self.speed[1] *= 1.0 - Self::FRICTION;
        self.position[0] += self.speed[0] * Self::SPEED_FACTOR;
        self.position[1] += self.speed[1] * Self::SPEED_FACTOR;

        true
    }

    /// Generate vertices for this particle (2-point segment strip).
    pub fn to_vertices(&self) -> Vec<f32> {
        let end = [
            self.position[0] + self.speed[0],
            self.position[1] + self.speed[1],
        ];
        build_strip_vertices(
            &[self.position, end],
            self.width,
            self.color,
        )
    }
}

// ---- Effects State ----

/// Container for all visual effects (arcs + particles).
pub struct EffectsState {
    pub arcs: Vec<(ElectricArc, f32, SegmentColor)>, // (arc, width, color)
    pub particles: Vec<Particle>,
    pub effects_buffer: Vec<f32>,  // triangle list vertices [x, y, z, u, v]
    pub rng: Rng,
    pub attractor: [f32; 2],
}

impl EffectsState {
    pub fn new(seed: u64) -> Self {
        EffectsState {
            arcs: Vec::new(),
            particles: Vec::new(),
            effects_buffer: Vec::with_capacity(4096),
            rng: Rng::new(seed.wrapping_add(7919)), // different seed than board
            attractor: [0.0, 0.0],
        }
    }

    /// Build electric arcs from the current board markings.
    /// Called when entering FreezeDuringZap phase.
    pub fn build_arcs_from_board(&mut self, board: &GameBoard, tile_size: f32, offset_x: f32, offset_y: f32) {
        self.arcs.clear();

        // Helper: get tile center position
        let tile_center = |x: usize, y: usize| -> [f32; 2] {
            [
                offset_x + x as f32 * tile_size + tile_size * 0.5,
                offset_y + y as f32 * tile_size + tile_size * 0.5,
            ]
        };

        // Pin positions
        let left_pin_x = offset_x - tile_size + tile_size * 0.5;
        let right_pin_x = offset_x + board.width as f32 * tile_size + tile_size * 0.5;

        // For each marker type, create arcs
        let configs: [(Marking, SegmentColor, u32, f32); 3] = [
            (Marking::Left, SegmentColor::Indigo, 4, 4.0),
            (Marking::Right, SegmentColor::Orange, 4, 4.0),
            (Marking::Ok, SegmentColor::SkyBlue, 3, 8.0),
        ];

        for &(marker, color, po2, width) in &configs {
            let arc_color = if marker == Marking::Ok {
                // Ok arcs to pins use Red, internal use SkyBlue
                color
            } else {
                color
            };

            for y in 0..board.height {
                // Left pin connection
                if board.get_marking(0, y) == marker {
                    if let Some(tile) = board.grid.get(0, y) {
                        if tile.has_connection(Direction::LEFT) {
                            let pin_center = [left_pin_x, offset_y + y as f32 * tile_size + tile_size * 0.5];
                            let tile_center = tile_center(0, y);
                            let pin_color = if marker == Marking::Ok { SegmentColor::Red } else { arc_color };
                            let arc = ElectricArc::new(pin_center, tile_center, po2, &mut self.rng);
                            self.arcs.push((arc, width, pin_color));
                        }
                    }
                }

                // Right pin connection
                if board.get_marking(board.width - 1, y) == marker {
                    if let Some(tile) = board.grid.get(board.width - 1, y) {
                        if tile.has_connection(Direction::RIGHT) {
                            let tile_center = tile_center(board.width - 1, y);
                            let pin_center = [right_pin_x, offset_y + y as f32 * tile_size + tile_size * 0.5];
                            let pin_color = if marker == Marking::Ok { SegmentColor::Red } else { arc_color };
                            let arc = ElectricArc::new(tile_center, pin_center, po2, &mut self.rng);
                            self.arcs.push((arc, width, pin_color));
                        }
                    }
                }

                // Internal connections
                for x in 0..board.width {
                    if board.get_marking(x, y) != marker {
                        continue;
                    }
                    if let Some(tile) = board.grid.get(x, y) {
                        // Horizontal: right connection
                        if tile.has_connection(Direction::RIGHT) && x + 1 < board.width {
                            if let Some(right) = board.grid.get(x + 1, y) {
                                if right.has_connection(Direction::LEFT) && board.get_marking(x + 1, y) == marker {
                                    let a = tile_center(x, y);
                                    let b = tile_center(x + 1, y);
                                    let arc = ElectricArc::new(a, b, po2, &mut self.rng);
                                    self.arcs.push((arc, width, arc_color));
                                }
                            }
                        }
                        // Vertical: down connection
                        if tile.has_connection(Direction::DOWN) && y + 1 < board.height {
                            if let Some(down) = board.grid.get(x, y + 1) {
                                if down.has_connection(Direction::UP) && board.get_marking(x, y + 1) == marker {
                                    let a = tile_center(x, y);
                                    let b = tile_center(x, y + 1);
                                    let arc = ElectricArc::new(a, b, po2, &mut self.rng);
                                    self.arcs.push((arc, width, arc_color));
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Spawn particles for Ok-marked tiles (called when zap occurs).
    pub fn spawn_zap_particles(&mut self, board: &GameBoard, tile_size: f32, offset_x: f32, offset_y: f32) {
        let speed_limit = 10.0f32;
        let count_per_tile = 10;
        let particle_width = 4.0;
        let lifetime = 2.0;

        // Set attractor at bottom of board
        self.attractor = [
            offset_x + (board.width as f32) * tile_size * 0.5,
            offset_y + 2.0 * tile_size * board.height as f32,
        ];

        for x in 0..board.width {
            for y in 0..board.height {
                if board.get_marking(x, y) == Marking::Ok {
                    let cx = offset_x + x as f32 * tile_size + tile_size * 0.5;
                    let cy = offset_y + y as f32 * tile_size + tile_size * 0.5;

                    for _ in 0..count_per_tile {
                        let sx = (self.rng.next_int(20000) as f32 / 1000.0) - 10.0;
                        let sy = (self.rng.next_int(20000) as f32 / 1000.0) - 10.0;
                        let color = SegmentColor::random(&mut self.rng);
                        self.particles.push(Particle::new(
                            [cx, cy],
                            [sx * speed_limit / 10.0, sy * speed_limit / 10.0],
                            particle_width,
                            color,
                            lifetime,
                        ));
                    }
                }
            }
        }
    }

    /// Advance effects: twitch arcs, update particles.
    pub fn tick(&mut self, dt: f32) {
        // Twitch all arcs
        for (arc, _, _) in &mut self.arcs {
            arc.twitch(0.05, &mut self.rng);
        }

        // Update particles
        let attractor = self.attractor;
        self.particles.retain_mut(|p| p.tick(attractor, dt));
    }

    /// Rebuild the effects vertex buffer (triangle list, 5 floats per vertex).
    pub fn rebuild_effects_buffer(&mut self) {
        self.effects_buffer.clear();

        // Arcs -> triangle strip -> triangle list
        for (arc, width, color) in &self.arcs {
            let strip = build_strip_vertices(&arc.points, *width, *color);
            let tris = strip_to_triangles(&strip, 5);
            self.effects_buffer.extend_from_slice(&tris);
        }

        // Particles -> triangle strip -> triangle list
        for p in &self.particles {
            let strip = p.to_vertices();
            let tris = strip_to_triangles(&strip, 5);
            self.effects_buffer.extend_from_slice(&tris);
        }
    }

    /// Clear all effects.
    pub fn clear(&mut self) {
        self.arcs.clear();
        self.particles.clear();
        self.effects_buffer.clear();
    }

    pub fn effects_vertex_count(&self) -> usize {
        self.effects_buffer.len() / 5
    }

    pub fn effects_buffer_ptr(&self) -> *const f32 {
        self.effects_buffer.as_ptr()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn electric_arc_generates_correct_point_count() {
        let mut rng = Rng::new(42);
        let arc = ElectricArc::new([0.0, 0.0], [100.0, 0.0], 3, &mut rng);
        assert_eq!(arc.points.len(), 9); // 2^3 + 1
    }

    #[test]
    fn electric_arc_po2_4() {
        let mut rng = Rng::new(42);
        let arc = ElectricArc::new([0.0, 0.0], [100.0, 0.0], 4, &mut rng);
        assert_eq!(arc.points.len(), 17); // 2^4 + 1
    }

    #[test]
    fn strip_vertices_for_simple_line() {
        let points = [[0.0, 0.0], [100.0, 0.0]];
        let verts = build_strip_vertices(&points, 4.0, SegmentColor::Red);
        // 2 points + 2 caps = 4 vertex pairs = 8 vertices * 5 floats
        assert_eq!(verts.len(), 8 * 5);
    }

    #[test]
    fn strip_to_triangles_correct_count() {
        // 6 vertices in strip = 4 triangles = 12 output vertices
        let strip = vec![0.0; 6 * 5]; // 6 verts, 5 floats each
        let tris = strip_to_triangles(&strip, 5);
        assert_eq!(tris.len() / 5, 12); // 4 triangles * 3 verts
    }

    #[test]
    fn particle_expires() {
        let mut p = Particle::new([0.0, 0.0], [1.0, 0.0], 4.0, SegmentColor::Red, 0.1);
        let alive = p.tick([0.0, 100.0], 0.2);
        assert!(!alive, "particle should expire");
    }

    #[test]
    fn effects_state_builds_arcs() {
        let board = GameBoard::new(3, 1, 0, 42);
        let mut effects = EffectsState::new(42);
        effects.build_arcs_from_board(&board, 50.0, 150.0, 25.0);
        // May or may not have arcs depending on initial random connections
        // Just verify it doesn't panic
    }
}
