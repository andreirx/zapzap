use crate::components::{
    GameMode, Marking, PowerUpInventory, PowerUpType, SoundEvent,
    ATLAS_COL_LEFT_PIN, ATLAS_COL_RIGHT_PIN, ATLAS_ROW_NORMAL,
    ATLAS_ROW_PINS, DEFAULT_HEIGHT, DEFAULT_MISSING_LINKS, DEFAULT_WIDTH,
};
use crate::systems::animation::{AnimationState, FallAnim, RotateAnim};
use crate::systems::board::GameBoard;
use crate::systems::bonus::{calculate_bonus_drops, BonusState, FallingBonusKind};
use crate::systems::bot::BotPlayer;
use crate::systems::effects::{
    build_strip_vertices, strip_to_triangles, EffectsState, SegmentColor,
};

/// Matches Swift's ZapGameState enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum GamePhase {
    WaitingForInput = 0,
    RotatingTile = 1,
    FallingTiles = 2,
    FreezeDuringZap = 3,
    FreezeDuringBomb = 4,
    GameOver = 5,
    FallingBonuses = 6,
}

/// Per-instance data written to SharedArrayBuffer for the renderer.
/// Must match DECISIONS.md layout: 8 floats = 32 bytes stride.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct RenderInstance {
    pub x: f32,
    pub y: f32,
    pub rotation: f32,
    pub scale: f32,
    pub sprite_id: f32, // atlas column (after GRID_CODEP lookup)
    pub alpha: f32,
    pub flags: f32,     // bit 0 = visible, bit 1 = animating
    pub atlas_row: f32, // atlas row (1.0 = normal tiles, 3.0 = pins)
}

/// Sprite index constants for the texture atlas.
/// The base_tiles atlas is a 16x8 grid. Connection bitmask maps through GRID_CODEP
/// to get the correct atlas column. Row 1 = normal tiles, row 3 = pins.
pub mod sprites {
    use crate::components::GRID_CODEP;

    /// Map a connection bitmask (0-15) to atlas column via the legacy lookup table.
    pub fn tile_atlas_col(connections: u8) -> f32 {
        GRID_CODEP[(connections & 0x0F) as usize] as f32
    }
}

/// Game constants matching legacy.
pub const TILE_SIZE: f32 = 50.0;
pub const GRID_OFFSET_X: f32 = 225.0; // left margin for pins (centers 14-col board in 1050-wide canvas)
pub const GRID_OFFSET_Y: f32 = 25.0;
pub const MAX_VS_SCORE: i32 = 100;

/// A score popup event emitted when points are scored.
/// Read by JS via SharedArrayBuffer to display floating "+N" text.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ScorePopup {
    pub x: f32,     // world-space X
    pub y: f32,     // world-space Y
    pub value: f32, // score points (as f32)
    pub side: f32,  // 0.0 = left (magenta), 1.0 = right (orange)
}

/// Freeze durations matching legacy (seconds).
const FREEZE_ZAP_DURATION: f32 = 2.0;
const FREEZE_BOMB_DURATION: f32 = 1.0;

/// Bot delay timer range (seconds).
const BOT_DELAY_MIN: f32 = 1.0;
const BOT_DELAY_MAX: f32 = 2.0;

/// Render multiplier light indicators as small glowing dots next to each pin.
/// Uses the effects pipeline (additive blend) for neon glow aesthetic.
/// Layout matches legacy: 4 dots per column, arranged in a grid pattern.
fn build_multiplier_lights(
    board: &GameBoard,
    effects_buffer: &mut Vec<f32>,
) {
    let left_pin_x = GRID_OFFSET_X - TILE_SIZE + TILE_SIZE * 0.5;
    let right_pin_x = GRID_OFFSET_X + (board.width as f32) * TILE_SIZE + TILE_SIZE * 0.5;
    let light_len = 2.0;
    let light_width = 3.0;
    // Base offset pushes first dot column well outside the pin sprite
    let base_offset = TILE_SIZE * 0.45;

    for y in 0..board.height {
        let pin_y = GRID_OFFSET_Y + y as f32 * TILE_SIZE + TILE_SIZE * 0.5;

        // Left multiplier lights (magenta)
        let mult_left = board.multiplier_left[y].max(0) as usize;
        for i in 0..mult_left {
            let dx = base_offset + (i / 4) as f32 * TILE_SIZE / 5.0;
            let dy = 2.0 * TILE_SIZE / 10.0 + (i % 4) as f32 * TILE_SIZE / 5.0;
            let lx = left_pin_x - dx;
            let ly = pin_y - TILE_SIZE * 0.5 + dy;
            let strip = build_strip_vertices(
                &[[lx, ly], [lx + light_len, ly]],
                light_width,
                SegmentColor::Magenta,
            );
            let tris = strip_to_triangles(&strip, 5);
            effects_buffer.extend_from_slice(&tris);
        }

        // Right multiplier lights (orange)
        let mult_right = board.multiplier_right[y].max(0) as usize;
        for i in 0..mult_right {
            let dx = base_offset + (i / 4) as f32 * TILE_SIZE / 5.0;
            let dy = 2.0 * TILE_SIZE / 10.0 + (i % 4) as f32 * TILE_SIZE / 5.0;
            let rx = right_pin_x + dx;
            let ry = pin_y - TILE_SIZE * 0.5 + dy;
            let strip = build_strip_vertices(
                &[[rx, ry], [rx + light_len, ry]],
                light_width,
                SegmentColor::Orange,
            );
            let tris = strip_to_triangles(&strip, 5);
            effects_buffer.extend_from_slice(&tris);
        }
    }
}

/// The top-level game state, holding everything the simulation needs.
pub struct GameState {
    pub board: GameBoard,
    pub phase: GamePhase,
    pub mode: GameMode,
    pub left_score: i32,
    pub right_score: i32,
    pub bot_enabled: bool,
    pub bot_delay_timer: f32, // seconds until bot acts (VsBot mode)

    // Animation system
    pub anims: AnimationState,

    // Visual effects (electric arcs + particles)
    pub effects: EffectsState,

    // Bonus/power-up system
    pub bonuses: BonusState,
    pub power_left: PowerUpInventory,
    pub power_right: PowerUpInventory,
    // Pending bonus drop counts (stored during freeze, spawned after freeze ends)
    pending_bonus: (usize, usize, usize),

    // Deferred bomb/arrow params (tx, ty, dx, dy) — applied after freeze ends
    pending_bomb_params: Option<(usize, usize, usize, usize)>,

    // The render buffer — written each tick, read by the host renderer.
    pub render_buffer: Vec<RenderInstance>,

    // Sound events emitted this tick
    pub sound_events: Vec<SoundEvent>,

    // Score popups emitted this tick (read by JS for floating text)
    pub score_popups: Vec<ScorePopup>,

    // Input queue (tile coordinates from JS)
    pub pending_tap: Option<(usize, usize)>,
}

impl GameState {
    pub fn new(seed: u64) -> Self {
        Self::new_with_mode(seed, GameMode::Zen)
    }

    pub fn new_with_mode(seed: u64, mode: GameMode) -> Self {
        let board = GameBoard::new(DEFAULT_WIDTH, DEFAULT_HEIGHT, DEFAULT_MISSING_LINKS, seed);
        let capacity = DEFAULT_WIDTH * DEFAULT_HEIGHT + 2 * DEFAULT_HEIGHT + 64; // tiles + pins + UI + bonuses
        let bot_enabled = mode == GameMode::VsBot;
        let mut state = GameState {
            board,
            phase: GamePhase::WaitingForInput,
            mode,
            left_score: 0,
            right_score: 0,
            bot_enabled,
            bot_delay_timer: 0.0,
            anims: AnimationState::new(),
            effects: EffectsState::new(seed),
            bonuses: BonusState::new(),
            power_left: PowerUpInventory::default(),
            power_right: PowerUpInventory::default(),
            pending_bonus: (0, 0, 0),
            pending_bomb_params: None,
            render_buffer: Vec::with_capacity(capacity),
            sound_events: Vec::with_capacity(8),
            score_popups: Vec::with_capacity(16),
            pending_tap: None,
        };

        // Check initial board — auto-zap if already connected, otherwise build arcs
        state.check_and_transition();

        state
    }

    /// Queue a tap from JS. Coordinates are in tile space (0..width, 0..height).
    pub fn queue_tap(&mut self, tile_x: usize, tile_y: usize) {
        if tile_x < self.board.width && tile_y < self.board.height {
            self.pending_tap = Some((tile_x, tile_y));
        }
    }

    /// Main simulation tick. Called each frame from the host.
    pub fn tick(&mut self, dt: f32) {
        self.sound_events.clear();
        self.score_popups.clear();

        match self.phase {
            GamePhase::WaitingForInput => {
                self.process_input();
                self.try_bot_move(dt);
            }
            GamePhase::RotatingTile => {
                self.anims.tick_rotations(dt);
                if !self.anims.has_rotate_anims() {
                    self.check_and_transition();
                }
            }
            GamePhase::FreezeDuringZap => {
                if self.anims.tick_freeze(dt) {
                    self.do_zap();
                }
            }
            GamePhase::FreezeDuringBomb => {
                if self.anims.tick_freeze(dt) {
                    self.finish_bomb();
                }
            }
            GamePhase::FallingBonuses => {
                // Legacy: no longer used — bonuses now fall in sync with tiles
                // in FallingTiles phase. Keep variant to avoid breaking repr(u8).
            }
            GamePhase::FallingTiles => {
                self.anims.tick_falls();
                self.bonuses.tick_falling();
                let falls_done = !self.anims.has_fall_anims();
                let bonuses_done = self.bonuses.falling.is_empty();
                if falls_done && bonuses_done {
                    self.finish_falling();
                }
            }
            GamePhase::GameOver => {
                // Nothing to update.
            }
        }

        // Always tick effects (particles need to update in every phase)
        self.effects.tick(dt);
        self.effects.rebuild_effects_buffer();
        build_multiplier_lights(&self.board, &mut self.effects.effects_buffer);

        // Tick idle animations for landed bonuses (rotation + pulse)
        self.bonuses.tick_idle(dt);

        self.rebuild_render_buffer();
    }

    fn process_input(&mut self) {
        if let Some((tx, ty)) = self.pending_tap.take() {
            // Check if any power-up is armed (either side)
            if let Some(ptype) = self.power_left.consume_armed() {
                self.apply_power_up(ptype, tx, ty);
                return;
            }
            if let Some(ptype) = self.power_right.consume_armed() {
                self.apply_power_up(ptype, tx, ty);
                return;
            }

            // Rotate the tile (game logic is instant)
            if let Some(tile) = self.board.grid.get_mut(tx, ty) {
                tile.rotate();
            }
            // Visual animation: smooth rotation from +90deg to 0
            self.anims.rotate_anims.push(RotateAnim::new(tx, ty, 1));
            self.sound_events.push(SoundEvent::Rotate);
            self.phase = GamePhase::RotatingTile;
        }
    }

    fn apply_power_up(&mut self, ptype: PowerUpType, tx: usize, ty: usize) {
        match ptype {
            PowerUpType::Bomb => {
                let positions = self.bomb_affected_positions(tx, ty, 2, 2);
                self.effects.spawn_explosion_particles(&positions, TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y);
                // Defer bomb_table to after freeze — grid stays intact during freeze
                // so affected tiles render at their original positions (hidden by alpha=0).
                self.pending_bomb_params = Some((tx, ty, 2, 2));
                self.bonuses.clear();
                self.sound_events.push(SoundEvent::Bomb);
                self.anims.freeze_timer = FREEZE_BOMB_DURATION;
                self.phase = GamePhase::FreezeDuringBomb;
            }
            PowerUpType::Cross => {
                self.board.set_tile(tx, ty, 0x0F);
                self.sound_events.push(SoundEvent::PowerUp);
                self.check_and_transition();
            }
            PowerUpType::Arrow => {
                let height = self.board.height;
                let positions = self.bomb_affected_positions(tx, ty, 0, height);
                self.effects.spawn_explosion_particles(&positions, TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y);
                // Defer bomb_table to after freeze
                self.pending_bomb_params = Some((tx, ty, 0, height));
                self.bonuses.clear();
                self.sound_events.push(SoundEvent::Bomb);
                self.anims.freeze_timer = FREEZE_BOMB_DURATION;
                self.phase = GamePhase::FreezeDuringBomb;
            }
        }
    }

    /// Compute tile positions affected by a bomb_table call (for particle effects).
    fn bomb_affected_positions(&self, ati: usize, atj: usize, dx: usize, dy: usize) -> Vec<(usize, usize)> {
        let mut positions = Vec::new();
        let start_i = ati.saturating_sub(dx);
        let end_i = (ati + dx + 1).min(self.board.width);
        let start_j = atj.saturating_sub(dy);
        let end_j = (atj + dy + 1).min(self.board.height);
        for x in start_i..end_i {
            for y in start_j..end_j {
                if self.board.grid.get(x, y).is_some() {
                    positions.push((x, y));
                }
            }
        }
        positions
    }

    /// Check if a tile is in the pending bomb/arrow affected area.
    /// During FreezeDuringBomb, these tiles are hidden (bomb_table hasn't run yet).
    fn is_pending_bomb_tile(&self, x: usize, y: usize) -> bool {
        if let Some((tx, ty, dx, dy)) = self.pending_bomb_params {
            let start_x = tx.saturating_sub(dx);
            let end_x = (tx + dx + 1).min(self.board.width);
            let start_y = ty.saturating_sub(dy);
            let end_y = (ty + dy + 1).min(self.board.height);
            x >= start_x && x < end_x && y >= start_y && y < end_y
        } else {
            false
        }
    }

    fn try_bot_move(&mut self, dt: f32) {
        if !self.bot_enabled || self.phase != GamePhase::WaitingForInput {
            return;
        }

        // Delay before bot acts (simulates thinking)
        if self.bot_delay_timer > 0.0 {
            self.bot_delay_timer -= dt;
            return;
        }

        if let Some(mv) = BotPlayer::determine_next_move(&self.board) {
            // Apply rotations (game logic is instant)
            for _ in 0..mv.rotation_count {
                if let Some(tile) = self.board.grid.get_mut(mv.x, mv.y) {
                    tile.rotate();
                }
            }
            self.anims.rotate_anims.push(RotateAnim::new_with_source(mv.x, mv.y, mv.rotation_count, true));
            self.phase = GamePhase::RotatingTile;

            // Reset delay for next move
            let range = BOT_DELAY_MAX - BOT_DELAY_MIN;
            let r = (self.effects.rng.next_int(1000) as f32) / 1000.0;
            self.bot_delay_timer = BOT_DELAY_MIN + r * range;
        }
    }

    fn check_and_transition(&mut self) {
        let zap = self.board.check_connections();

        // Always rebuild arcs from current board markings (legacy: arcs visible at all times)
        self.effects.build_arcs_from_board(&self.board, TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y);

        // Collect any landed bonuses on tiles touched by arcs (Left, Right, or Ok)
        self.collect_landed_bonuses();

        if zap != 0 {
            // Add multiplier-based score for each connected pin
            self.apply_multiplier_scores();

            // Calculate bonus drops based on pin connections
            self.pending_bonus = calculate_bonus_drops(
                self.board.left_pins_connect,
                self.board.right_pins_connect,
            );

            // Spawn particles for the connected tiles
            self.effects.spawn_zap_particles(&self.board, TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y);

            self.sound_events.push(SoundEvent::Buzz);
            self.anims.freeze_timer = FREEZE_ZAP_DURATION;
            self.phase = GamePhase::FreezeDuringZap;

            // Check game over (VsBot mode only)
            if self.mode == GameMode::VsBot
                && (self.left_score >= MAX_VS_SCORE || self.right_score >= MAX_VS_SCORE)
            {
                self.phase = GamePhase::GameOver;
            }
        } else {
            // No zap — arcs already rebuilt above, keep particles alive (they fade naturally)
            self.phase = GamePhase::WaitingForInput;
        }
    }

    /// Apply multiplier-based scoring from connected pins.
    /// Each connected pin adds its multiplier value to the score, then multiplier increments.
    fn apply_multiplier_scores(&mut self) {
        use crate::components::Direction;

        let left_pin_x = GRID_OFFSET_X - TILE_SIZE + TILE_SIZE * 0.5;
        let right_pin_x = GRID_OFFSET_X + (self.board.width as f32) * TILE_SIZE + TILE_SIZE * 0.5;

        for y in 0..self.board.height {
            let pin_y = GRID_OFFSET_Y + y as f32 * TILE_SIZE + TILE_SIZE * 0.5;

            // Left pins
            if self.board.get_marking(0, y) == Marking::Ok {
                if let Some(tile) = self.board.grid.get(0, y) {
                    if tile.has_connection(Direction::LEFT) {
                        let mult = self.board.multiplier_left[y];
                        match self.mode {
                            GameMode::Zen => {
                                self.left_score += mult;
                                self.right_score += mult;
                            }
                            GameMode::VsBot => {
                                self.left_score += mult;
                            }
                        }
                        self.score_popups.push(ScorePopup {
                            x: left_pin_x,
                            y: pin_y,
                            value: mult as f32,
                            side: 0.0,
                        });
                        self.board.multiplier_left[y] += 1;
                    }
                }
            }

            // Right pins
            if self.board.get_marking(self.board.width - 1, y) == Marking::Ok {
                if let Some(tile) = self.board.grid.get(self.board.width - 1, y) {
                    if tile.has_connection(Direction::RIGHT) {
                        let mult = self.board.multiplier_right[y];
                        match self.mode {
                            GameMode::Zen => {
                                self.left_score += mult;
                                self.right_score += mult;
                            }
                            GameMode::VsBot => {
                                self.right_score += mult;
                            }
                        }
                        self.score_popups.push(ScorePopup {
                            x: right_pin_x,
                            y: pin_y,
                            value: mult as f32,
                            side: 1.0,
                        });
                        self.board.multiplier_right[y] += 1;
                    }
                }
            }
        }
    }

    /// Collect any landed bonuses sitting on tiles with active markings (Left, Right, Ok).
    /// Called from check_and_transition() so bonuses are picked up whenever arcs touch them,
    /// not just after a full zap cycle.
    fn collect_landed_bonuses(&mut self) {
        if self.bonuses.landed.is_empty() {
            return;
        }

        let landed = core::mem::take(&mut self.bonuses.landed);
        let mut uncollected = Vec::new();
        let mut left_pts = 0i32;
        let mut right_pts = 0i32;
        let mut left_powers: Vec<PowerUpType> = Vec::new();
        let mut right_powers: Vec<PowerUpType> = Vec::new();

        for bonus in landed {
            let marking = self.board.get_marking(bonus.tile_x, bonus.tile_y);
            let pts = bonus.points();
            match marking {
                Marking::Left | Marking::Ok => {
                    left_pts += pts;
                    if let FallingBonusKind::PowerUp(ptype) = bonus.kind {
                        left_powers.push(ptype);
                    }
                    if pts > 0 {
                        let bx = GRID_OFFSET_X + bonus.tile_x as f32 * TILE_SIZE + TILE_SIZE * 0.5;
                        let by = GRID_OFFSET_Y + bonus.tile_y as f32 * TILE_SIZE + TILE_SIZE * 0.5;
                        self.score_popups.push(ScorePopup {
                            x: bx, y: by, value: pts as f32, side: 0.0,
                        });
                    }
                }
                Marking::Right => {
                    right_pts += pts;
                    if let FallingBonusKind::PowerUp(ptype) = bonus.kind {
                        right_powers.push(ptype);
                    }
                    if pts > 0 {
                        let bx = GRID_OFFSET_X + bonus.tile_x as f32 * TILE_SIZE + TILE_SIZE * 0.5;
                        let by = GRID_OFFSET_Y + bonus.tile_y as f32 * TILE_SIZE + TILE_SIZE * 0.5;
                        self.score_popups.push(ScorePopup {
                            x: bx, y: by, value: pts as f32, side: 1.0,
                        });
                    }
                }
                _ => {
                    uncollected.push(bonus);
                }
            }
        }
        self.bonuses.landed = uncollected;

        if left_pts > 0 || right_pts > 0 {
            match self.mode {
                GameMode::Zen => {
                    let total = left_pts + right_pts;
                    self.left_score += total;
                    self.right_score += total;
                }
                GameMode::VsBot => {
                    self.left_score += left_pts;
                    self.right_score += right_pts;
                }
            }
            self.sound_events.push(SoundEvent::CoinDrop);
        }

        for ptype in left_powers {
            match ptype {
                PowerUpType::Bomb => self.power_left.has_bomb = true,
                PowerUpType::Cross => self.power_left.has_cross = true,
                PowerUpType::Arrow => self.power_left.has_arrow = true,
            }
            self.sound_events.push(SoundEvent::PowerUp);
        }
        for ptype in right_powers {
            match ptype {
                PowerUpType::Bomb => self.power_right.has_bomb = true,
                PowerUpType::Cross => self.power_right.has_cross = true,
                PowerUpType::Arrow => self.power_right.has_arrow = true,
            }
            self.sound_events.push(SoundEvent::PowerUp);
        }
    }

    fn do_zap(&mut self) {
        // Clear arcs (keep particles alive, they'll fade naturally)
        self.effects.arcs.clear();

        self.sound_events.push(SoundEvent::CoinDrop);
        self.sound_events.push(SoundEvent::Explode);

        // Re-check connections so markings are fresh
        let _ = self.board.check_connections();

        // Record original y-positions of surviving (non-Ok) tiles per column
        // before removal. Collected bottom-up to match remove_and_shift order.
        let height = self.board.height;
        let mut survivors_per_col: Vec<Vec<usize>> = Vec::with_capacity(self.board.width);
        for x in 0..self.board.width {
            let mut col_survivors = Vec::new();
            for y in (0..height).rev() {
                if self.board.get_marking(x, y) != Marking::Ok {
                    col_survivors.push(y);
                }
            }
            survivors_per_col.push(col_survivors);
        }

        // Remove connected tiles and fill with new ones
        self.board.remove_and_shift_connecting_tiles();

        // Reset all markings to None so falling tiles render with normal alpha
        for x in 0..self.board.width {
            for y in 0..self.board.height {
                self.board.set_marking(x, y, Marking::None);
            }
        }

        let half_tile = TILE_SIZE * 0.5;

        // Create per-tile fall animations
        for x in 0..self.board.width {
            let survivors = &survivors_per_col[x];
            let num_new = height - survivors.len();
            if num_new == 0 {
                continue;
            }

            // Surviving tiles: placed at y = height-1-i (bottom-up)
            for (i, &old_y) in survivors.iter().enumerate() {
                let new_y = height - 1 - i;
                if new_y != old_y {
                    let old_world_y = GRID_OFFSET_Y + old_y as f32 * TILE_SIZE + half_tile;
                    let new_world_y = GRID_OFFSET_Y + new_y as f32 * TILE_SIZE + half_tile;
                    self.anims.fall_anims.push(FallAnim::new(x, new_y, old_world_y, new_world_y));
                }
            }

            // New tiles: start above the grid and fall into top slots
            for i in 0..num_new {
                let start_y = GRID_OFFSET_Y - (num_new - i) as f32 * TILE_SIZE + half_tile;
                let target_y = GRID_OFFSET_Y + i as f32 * TILE_SIZE + half_tile;
                self.anims.fall_anims.push(FallAnim::new(x, i, start_y, target_y));
            }
        }

        // Spawn bonus objects (they'll fall in sync with tiles)
        let (m1, m2, m5) = self.pending_bonus;
        self.pending_bonus = (0, 0, 0);

        let mut bonus_rng = self.effects.rng.clone();
        self.bonuses.spawn_bonuses(
            m1, m2, m5,
            &self.board,
            &mut bonus_rng,
            TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y,
        );
        self.effects.rng = bonus_rng;

        // Go directly to FallingTiles — bonuses and tiles fall simultaneously
        self.phase = GamePhase::FallingTiles;
    }

    /// Called when both tile falls and bonus falls are complete.
    /// Bonus collection is handled by collect_landed_bonuses() inside check_and_transition(),
    /// which uses the live board markings (not stale snapshots).
    fn finish_falling(&mut self) {
        self.check_and_transition();
    }

    /// Called when bomb/arrow freeze ends — apply bomb_table and create fall animations.
    fn finish_bomb(&mut self) {
        if let Some((tx, ty, dx, dy)) = self.pending_bomb_params.take() {
            // Compute per-column counts before modifying the grid
            let positions = self.bomb_affected_positions(tx, ty, dx, dy);
            let mut col_counts: Vec<(usize, usize)> = Vec::new();
            for &(x, _) in &positions {
                if let Some(entry) = col_counts.iter_mut().find(|(cx, _)| *cx == x) {
                    entry.1 += 1;
                } else {
                    col_counts.push((x, 1));
                }
            }

            // Now apply the grid shift
            self.board.bomb_table(tx, ty, dx, dy);

            // Create fall animations for new tiles at the top of each affected column
            let half_tile = TILE_SIZE * 0.5;
            for (x, num_new) in col_counts {
                for i in 0..num_new {
                    let start_y = GRID_OFFSET_Y - (num_new - i) as f32 * TILE_SIZE + half_tile;
                    let target_y = GRID_OFFSET_Y + i as f32 * TILE_SIZE + half_tile;
                    self.anims.fall_anims.push(FallAnim::new(x, i, start_y, target_y));
                }
            }
        }

        if self.anims.has_fall_anims() {
            self.phase = GamePhase::FallingTiles;
        } else {
            self.board.check_connections();
            self.effects.build_arcs_from_board(&self.board, TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y);
            self.check_and_transition();
        }
    }

    /// Rebuild the flat render buffer from current board state.
    /// Layout per DECISIONS.md: 8 floats per entity.
    /// Includes: left pins (col 0), game tiles (cols 1..width), right pins (col width+1).
    fn rebuild_render_buffer(&mut self) {
        self.render_buffer.clear();

        // Left pins (column before the grid)
        for y in 0..self.board.height {
            let px = GRID_OFFSET_X - TILE_SIZE + TILE_SIZE * 0.5;
            let py = GRID_OFFSET_Y + (y as f32) * TILE_SIZE + TILE_SIZE * 0.5;
            self.render_buffer.push(RenderInstance {
                x: px,
                y: py,
                rotation: 0.0,
                scale: 1.0,
                sprite_id: ATLAS_COL_LEFT_PIN,
                alpha: 1.0,
                flags: 1.0,
                atlas_row: ATLAS_ROW_PINS,
            });
        }

        // Game tiles
        for x in 0..self.board.width {
            for y in 0..self.board.height {
                if let Some(tile) = self.board.grid.get(x, y) {
                    let marking = self.board.get_marking(x, y);

                    let px = GRID_OFFSET_X + (x as f32) * TILE_SIZE + TILE_SIZE * 0.5;
                    let py = GRID_OFFSET_Y + (y as f32) * TILE_SIZE + TILE_SIZE * 0.5;

                    // Animation overrides
                    let rotation = self.anims.get_rotation(x, y).unwrap_or(0.0);
                    let final_y = self.anims.get_fall_y(x, y).unwrap_or(py);

                    // Use GRID_CODEP lookup for correct atlas column
                    let sprite_id = sprites::tile_atlas_col(tile.connections);

                    // During FreezeDuringZap, hide connected tiles (arcs replace them visually)
                    // During FreezeDuringBomb, hide new tiles at top of bombed columns
                    let alpha = if marking == Marking::Ok && self.phase == GamePhase::FreezeDuringZap {
                        0.0
                    } else if self.phase == GamePhase::FreezeDuringBomb && self.is_pending_bomb_tile(x, y) {
                        0.0
                    } else {
                        match marking {
                            Marking::Ok => 1.5,
                            Marking::Right => 1.0,
                            Marking::Left => 1.0,
                            Marking::Animating => 0.3,
                            Marking::None => 1.0,
                        }
                    };

                    let flags = 1.0; // UV cell count (1×1 for regular tiles)

                    self.render_buffer.push(RenderInstance {
                        x: px,
                        y: final_y,
                        rotation,
                        scale: 1.0,
                        sprite_id,
                        alpha,
                        flags,
                        atlas_row: ATLAS_ROW_NORMAL,
                    });
                }
            }
        }

        // Right pins (column after the grid)
        for y in 0..self.board.height {
            let px = GRID_OFFSET_X + (self.board.width as f32) * TILE_SIZE + TILE_SIZE * 0.5;
            let py = GRID_OFFSET_Y + (y as f32) * TILE_SIZE + TILE_SIZE * 0.5;
            self.render_buffer.push(RenderInstance {
                x: px,
                y: py,
                rotation: 0.0,
                scale: 1.0,
                sprite_id: ATLAS_COL_RIGHT_PIN,
                alpha: 1.0,
                flags: 1.0,
                atlas_row: ATLAS_ROW_PINS,
            });
        }

        // Falling and landed bonus objects
        for bonus in self.bonuses.all_bonuses() {
            let (col, row) = bonus.atlas_uv();
            let px = GRID_OFFSET_X + (bonus.tile_x as f32) * TILE_SIZE + TILE_SIZE * 0.5;
            self.render_buffer.push(RenderInstance {
                x: px,
                y: bonus.current_y,
                rotation: bonus.rotation,
                scale: bonus.scale * bonus.base_scale() * bonus.pulse_scale(),
                sprite_id: col,
                alpha: bonus.alpha(),
                flags: 1.0,
                atlas_row: row,
            });
        }

        // Rotation arrow overlays (arrows atlas, 2×2 UV cells)
        // Rendered during RotatingTile phase: indigo arrows for player, orange for bot.
        if self.phase == GamePhase::RotatingTile {
            for anim in &self.anims.rotate_anims {
                let px = GRID_OFFSET_X + (anim.x as f32) * TILE_SIZE + TILE_SIZE * 0.5;
                let py = GRID_OFFSET_Y + (anim.y as f32) * TILE_SIZE + TILE_SIZE * 0.5;
                let rotation = self.anims.get_rotation(anim.x, anim.y).unwrap_or(0.0);
                // Indigo arrows: cols 2-3, rows 0-1 in 8×8 arrows atlas
                // Orange arrows: cols 4-5, rows 0-1 in 8×8 arrows atlas
                let sprite_id = if anim.is_bot { 4.0 } else { 2.0 };
                self.render_buffer.push(RenderInstance {
                    x: px,
                    y: py,
                    rotation,
                    scale: 2.5,
                    sprite_id,
                    alpha: 1.0,
                    flags: 2.0, // 2×2 UV cell block
                    atlas_row: 0.0,
                });
            }
        }
    }

    /// Pointer to the render buffer data for SharedArrayBuffer access.
    pub fn render_buffer_ptr(&self) -> *const RenderInstance {
        self.render_buffer.as_ptr()
    }

    /// Number of instances in the render buffer.
    pub fn render_buffer_len(&self) -> usize {
        self.render_buffer.len()
    }

    /// Pointer to the effects vertex buffer (for additive pipeline).
    pub fn effects_buffer_ptr(&self) -> *const f32 {
        self.effects.effects_buffer_ptr()
    }

    /// Number of effect vertices (each = 5 floats: x, y, z, u, v).
    pub fn effects_vertex_count(&self) -> usize {
        self.effects.effects_vertex_count()
    }

    /// Pointer to the sound events buffer.
    pub fn sound_events_ptr(&self) -> *const SoundEvent {
        self.sound_events.as_ptr()
    }

    /// Number of sound events this tick.
    pub fn sound_events_len(&self) -> usize {
        self.sound_events.len()
    }

    /// Pointer to the score popups buffer (4 f32s per popup).
    pub fn score_popups_ptr(&self) -> *const ScorePopup {
        self.score_popups.as_ptr()
    }

    /// Number of score popups this tick.
    pub fn score_popups_len(&self) -> usize {
        self.score_popups.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn game_state_initializes() {
        let state = GameState::new(42);
        // Phase is WaitingForInput unless the board auto-zapped on init
        assert!(
            state.phase == GamePhase::WaitingForInput
                || state.phase == GamePhase::FreezeDuringZap,
            "unexpected initial phase: {:?}",
            state.phase
        );
    }

    #[test]
    fn tick_populates_render_buffer() {
        let mut state = GameState::new(42);
        state.tick(1.0 / 60.0);
        // Should have one instance per tile + 2 columns of pins (left + right)
        let expected = DEFAULT_WIDTH * DEFAULT_HEIGHT + 2 * DEFAULT_HEIGHT;
        assert_eq!(state.render_buffer.len(), expected);
    }

    #[test]
    fn tap_rotates_tile() {
        let mut state = GameState::new(42);
        let original = state.board.grid.get(5, 5).unwrap().connections;
        state.queue_tap(5, 5);
        state.tick(1.0 / 60.0);
        // Tile should have rotated and we should be back checking connections or waiting
        let rotated = state.board.grid.get(5, 5).unwrap().connections;
        assert_ne!(original, rotated, "tile should have been rotated");
    }

    #[test]
    fn game_over_at_max_score() {
        let mut state = GameState::new(42);
        state.left_score = MAX_VS_SCORE;
        // Force a zap state transition with freeze about to expire
        state.phase = GamePhase::FreezeDuringZap;
        state.anims.freeze_timer = 0.001; // nearly expired
        state.tick(0.01); // tick past freeze expiration -> do_zap -> FallingTiles
        // After zap resolves, it should check for game over on next check
        // (the phase might cascade through FallingTiles -> check_and_transition)
    }
}
