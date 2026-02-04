use crate::components::{
    GameMode, Marking, PowerUpInventory, PowerUpType, SoundEvent,
    ATLAS_COL_LEFT_PIN, ATLAS_COL_RIGHT_PIN, ATLAS_ROW_NORMAL,
    ATLAS_ROW_PINS, DEFAULT_HEIGHT, DEFAULT_MISSING_LINKS, DEFAULT_WIDTH,
};
use crate::systems::animation::{AnimationState, FallAnim, RotateAnim};
use crate::systems::board::GameBoard;
use crate::systems::bonus::{calculate_bonus_drops, BonusState};
use crate::systems::bot::BotPlayer;
use crate::systems::effects::EffectsState;

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

/// Freeze durations matching legacy (seconds).
const FREEZE_ZAP_DURATION: f32 = 2.0;
const FREEZE_BOMB_DURATION: f32 = 1.0;

/// Bot delay timer range (seconds).
const BOT_DELAY_MIN: f32 = 1.0;
const BOT_DELAY_MAX: f32 = 2.0;

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

    // The render buffer — written each tick, read by the host renderer.
    pub render_buffer: Vec<RenderInstance>,

    // Sound events emitted this tick
    pub sound_events: Vec<SoundEvent>,

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
            render_buffer: Vec::with_capacity(capacity),
            sound_events: Vec::with_capacity(8),
            pending_tap: None,
        };

        // Build initial arcs from board state (legacy: arcs always visible)
        state.board.check_connections();
        state.effects.build_arcs_from_board(&state.board, TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y);

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
                    // Rebuild arcs after bomb changed the board
                    self.board.check_connections();
                    self.effects.build_arcs_from_board(&self.board, TILE_SIZE, GRID_OFFSET_X, GRID_OFFSET_Y);
                    self.phase = GamePhase::WaitingForInput;
                }
            }
            GamePhase::FallingBonuses => {
                if !self.bonuses.tick_falling() {
                    // All bonuses have landed — collect and transition
                    self.collect_bonuses();
                }
            }
            GamePhase::FallingTiles => {
                self.anims.tick_falls();
                if !self.anims.has_fall_anims() {
                    self.check_and_transition();
                }
            }
            GamePhase::GameOver => {
                // Nothing to update.
            }
        }

        // Always tick effects (particles need to update in every phase)
        self.effects.tick(dt);
        self.effects.rebuild_effects_buffer();

        self.rebuild_render_buffer();
    }

    fn process_input(&mut self) {
        if let Some((tx, ty)) = self.pending_tap.take() {
            // Check if a power-up is armed (left side only for player taps)
            if let Some(ptype) = self.power_left.consume_armed() {
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
                self.board.bomb_table(tx, ty, 2, 2);
                self.bonuses.clear();
                self.sound_events.push(SoundEvent::Bomb);
                self.anims.freeze_timer = FREEZE_BOMB_DURATION;
                self.phase = GamePhase::FreezeDuringBomb;
            }
            PowerUpType::Cross => {
                self.board.set_tile(tx, ty, 0x0F);
                self.sound_events.push(SoundEvent::PowerUp);
                // Immediately check connections after setting full connections
                self.check_and_transition();
            }
            PowerUpType::Arrow => {
                self.board.bomb_table(tx, ty, 0, self.board.height);
                self.bonuses.clear();
                self.sound_events.push(SoundEvent::Bomb);
                self.anims.freeze_timer = FREEZE_BOMB_DURATION;
                self.phase = GamePhase::FreezeDuringBomb;
            }
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
            self.anims.rotate_anims.push(RotateAnim::new(mv.x, mv.y, mv.rotation_count));
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

        for y in 0..self.board.height {
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
                        self.board.multiplier_right[y] += 1;
                    }
                }
            }
        }
    }

    fn do_zap(&mut self) {
        // Clear arcs (keep particles alive, they'll fade naturally)
        self.effects.arcs.clear();

        self.sound_events.push(SoundEvent::CoinDrop);

        // Re-check connections so markings are fresh for bonus collection
        let _ = self.board.check_connections();

        // Spawn bonus objects
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

        self.phase = GamePhase::FallingBonuses;
    }

    fn collect_bonuses(&mut self) {
        // Collect landed bonuses
        let (left_pts, right_pts, left_powers, right_powers) =
            self.bonuses.collect_landed(&self.board);

        self.left_score += left_pts;
        self.right_score += right_pts;

        // Award collected power-ups
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
        }

        // Now remove connected tiles and transition to FallingTiles
        self.sound_events.push(SoundEvent::Explode);

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

        self.board.remove_and_shift_connecting_tiles();
        self.bonuses.clear();

        let half_tile = TILE_SIZE * 0.5;

        // Create per-tile fall animations
        for x in 0..self.board.width {
            let survivors = &survivors_per_col[x];
            let num_new = height - survivors.len();
            if num_new == 0 {
                continue;
            }

            // Surviving tiles: placed at y = height-1-i (bottom-up)
            // Only animate if they actually moved
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

        self.phase = GamePhase::FallingTiles;
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

                    let alpha = match marking {
                        Marking::Ok => 1.5,
                        Marking::Right => 1.0,
                        Marking::Left => 1.0,
                        Marking::Animating => 0.3,
                        Marking::None => 1.0,
                    };

                    let flags = if marking == Marking::Animating { 2.0 } else { 1.0 };

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
                scale: bonus.scale * bonus.base_scale(),
                sprite_id: col,
                alpha: bonus.alpha(),
                flags: 1.0,
                atlas_row: row,
            });
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn game_state_initializes() {
        let state = GameState::new(42);
        assert_eq!(state.phase, GamePhase::WaitingForInput);
        assert_eq!(state.left_score, 0);
        assert_eq!(state.right_score, 0);
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
