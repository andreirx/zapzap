use std::cell::RefCell;
use wasm_bindgen::prelude::*;

use crate::components::{GameMode, PowerUpType};
use crate::state::GameState;

thread_local! {
    static GAME: RefCell<Option<GameState>> = RefCell::new(None);
}

fn with_game<R>(f: impl FnOnce(&mut GameState) -> R) -> R {
    GAME.with(|cell| {
        let mut borrow = cell.borrow_mut();
        let state = borrow.as_mut().expect("Game not initialized. Call init_game() first.");
        f(state)
    })
}

#[wasm_bindgen]
pub fn init_game(seed: f64) {
    let state = GameState::new(seed as u64);
    GAME.with(|cell| {
        *cell.borrow_mut() = Some(state);
    });
    log::info!("zapzap-sim: game initialized with seed {}", seed as u64);
}

/// Initialize with a specific game mode.
/// mode: 0 = Zen, 1 = VsBot
#[wasm_bindgen]
pub fn init_game_with_mode(seed: f64, mode: u8) {
    let game_mode = match mode {
        1 => GameMode::VsBot,
        _ => GameMode::Zen,
    };
    let state = GameState::new_with_mode(seed as u64, game_mode);
    GAME.with(|cell| {
        *cell.borrow_mut() = Some(state);
    });
    log::info!("zapzap-sim: game initialized with seed {}, mode {:?}", seed as u64, game_mode);
}

/// Returns the current game mode (0=Zen, 1=VsBot).
#[wasm_bindgen]
pub fn get_game_mode() -> u8 {
    with_game(|g| g.mode as u8)
}

#[wasm_bindgen]
pub fn tick_game(dt: f32) {
    with_game(|g| g.tick(dt));
}

#[wasm_bindgen]
pub fn tap_tile(x: u32, y: u32) {
    with_game(|g| g.queue_tap(x as usize, y as usize));
}

#[wasm_bindgen]
pub fn enable_bot(enabled: bool) {
    with_game(|g| g.bot_enabled = enabled);
}

/// Returns a pointer to the render instance buffer (for SharedArrayBuffer reads).
#[wasm_bindgen]
pub fn get_render_buffer_ptr() -> *const f32 {
    with_game(|g| g.render_buffer_ptr() as *const f32)
}

/// Returns the number of render instances.
#[wasm_bindgen]
pub fn get_render_buffer_len() -> u32 {
    with_game(|g| g.render_buffer_len() as u32)
}

/// Returns the current game phase as a u8.
#[wasm_bindgen]
pub fn get_game_phase() -> u8 {
    with_game(|g| g.phase as u8)
}

/// Returns left player score.
#[wasm_bindgen]
pub fn get_left_score() -> i32 {
    with_game(|g| g.left_score)
}

/// Returns right player score.
#[wasm_bindgen]
pub fn get_right_score() -> i32 {
    with_game(|g| g.right_score)
}

/// Returns the board width.
#[wasm_bindgen]
pub fn get_board_width() -> u32 {
    with_game(|g| g.board.width as u32)
}

/// Returns the board height.
#[wasm_bindgen]
pub fn get_board_height() -> u32 {
    with_game(|g| g.board.height as u32)
}

/// Returns a pointer to the sound events buffer (u8 per event).
#[wasm_bindgen]
pub fn get_sound_events_ptr() -> *const u8 {
    with_game(|g| g.sound_events_ptr() as *const u8)
}

/// Returns the number of sound events emitted this tick.
#[wasm_bindgen]
pub fn get_sound_events_len() -> u32 {
    with_game(|g| g.sound_events_len() as u32)
}

/// Returns a pointer to the effects vertex buffer (for additive pipeline).
#[wasm_bindgen]
pub fn get_effects_buffer_ptr() -> *const f32 {
    with_game(|g| g.effects_buffer_ptr())
}

/// Returns the number of effect vertices (5 floats each: x, y, z, u, v).
#[wasm_bindgen]
pub fn get_effects_vertex_count() -> u32 {
    with_game(|g| g.effects_vertex_count() as u32)
}

/// Returns a pointer to the score popups buffer (4 f32s per popup: x, y, value, side).
#[wasm_bindgen]
pub fn get_score_popups_ptr() -> *const f32 {
    with_game(|g| g.score_popups_ptr() as *const f32)
}

/// Returns the number of score popups emitted this tick.
#[wasm_bindgen]
pub fn get_score_popups_len() -> u32 {
    with_game(|g| g.score_popups_len() as u32)
}

/// Reset the game with a new seed.
#[wasm_bindgen]
pub fn reset_game(seed: f64) {
    let state = GameState::new(seed as u64);
    GAME.with(|cell| {
        *cell.borrow_mut() = Some(state);
    });
}

/// Toggle arm/disarm a power-up on the left side.
/// ptype: 0=Bomb, 1=Cross, 2=Arrow
/// Returns true if the power-up is now armed.
#[wasm_bindgen]
pub fn arm_power_left(ptype: u8) -> bool {
    let power_type = match ptype {
        0 => PowerUpType::Bomb,
        1 => PowerUpType::Cross,
        2 => PowerUpType::Arrow,
        _ => return false,
    };
    with_game(|g| g.power_left.toggle_arm(power_type))
}

/// Toggle arm/disarm a power-up on the right side.
#[wasm_bindgen]
pub fn arm_power_right(ptype: u8) -> bool {
    let power_type = match ptype {
        0 => PowerUpType::Bomb,
        1 => PowerUpType::Cross,
        2 => PowerUpType::Arrow,
        _ => return false,
    };
    with_game(|g| g.power_right.toggle_arm(power_type))
}

/// Get power-up state as a packed u16.
/// Bits 0-2: left has (bomb, cross, arrow)
/// Bits 3-5: right has (bomb, cross, arrow)
/// Bits 6-8: left armed (bomb, cross, arrow) — only one can be set
/// Bits 9-11: right armed (bomb, cross, arrow)
#[wasm_bindgen]
pub fn get_power_state() -> u16 {
    with_game(|g| {
        let mut bits: u16 = 0;
        if g.power_left.has_bomb { bits |= 1 << 0; }
        if g.power_left.has_cross { bits |= 1 << 1; }
        if g.power_left.has_arrow { bits |= 1 << 2; }
        if g.power_right.has_bomb { bits |= 1 << 3; }
        if g.power_right.has_cross { bits |= 1 << 4; }
        if g.power_right.has_arrow { bits |= 1 << 5; }
        match g.power_left.armed {
            Some(PowerUpType::Bomb) => bits |= 1 << 6,
            Some(PowerUpType::Cross) => bits |= 1 << 7,
            Some(PowerUpType::Arrow) => bits |= 1 << 8,
            None => {}
        }
        match g.power_right.armed {
            Some(PowerUpType::Bomb) => bits |= 1 << 9,
            Some(PowerUpType::Cross) => bits |= 1 << 10,
            Some(PowerUpType::Arrow) => bits |= 1 << 11,
            None => {}
        }
        bits
    })
}
