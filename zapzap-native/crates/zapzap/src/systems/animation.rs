use std::f32::consts::FRAC_PI_2;

/// Rotation animation for a tile being tapped.
/// Linear interpolation over 0.2s from start_rotation to end_rotation.
/// In Y-DOWN coordinates: positive angle = clockwise visual.
/// Game logic rotates connections instantly (CCW via bit-shift left).
/// Visual starts at -count*PI/2 and animates to 0 (sweeps CW back to rest).
/// Wait — user confirmed: start at +count*PI/2, animate to 0.
/// Positive start = CW offset, animating to 0 = visual CCW sweep.
#[derive(Debug, Clone)]
pub struct RotateAnim {
    pub x: usize,
    pub y: usize,
    pub start_rotation: f32,
    pub end_rotation: f32,
    pub progress: f32,    // 0.0 -> 1.0
    pub duration: f32,    // seconds (0.2)
}

impl RotateAnim {
    pub fn new(x: usize, y: usize, rotation_count: usize) -> Self {
        let count = rotation_count.max(1) as f32;
        RotateAnim {
            x,
            y,
            start_rotation: count * FRAC_PI_2, // positive = CW offset; animates CCW back to 0
            end_rotation: 0.0,
            progress: 0.0,
            duration: 0.2,
        }
    }

    /// Returns current rotation angle. Returns None when complete.
    pub fn tick(&mut self, dt: f32) -> Option<f32> {
        self.progress += dt / self.duration;
        if self.progress >= 1.0 {
            return None;
        }
        let t = self.progress;
        Some(self.start_rotation + (self.end_rotation - self.start_rotation) * t)
    }
}

/// Gravity-based fall animation for tiles after a zap removes tiles below.
/// Physics: speed += gravity * dt, speed *= (1.0 - friction), y += speed
#[derive(Debug, Clone)]
pub struct FallAnim {
    pub x: usize,
    pub y: usize,
    pub current_y: f32,   // current world-space Y
    pub target_y: f32,    // target world-space Y (where the tile should land)
    pub speed: f32,       // current vertical speed (pixels/frame)
}

impl FallAnim {
    const GRAVITY: f32 = 9.8;
    const FRICTION: f32 = 0.005;
    const SPEED_FACTOR: f32 = 1.0;
    const DT: f32 = 1.0 / 60.0;

    pub fn new(x: usize, y: usize, start_y: f32, target_y: f32) -> Self {
        FallAnim {
            x,
            y,
            current_y: start_y,
            target_y,
            speed: 0.0,
        }
    }

    /// Advance physics one frame. Returns current Y, or None when settled.
    pub fn tick(&mut self) -> Option<f32> {
        self.speed += Self::GRAVITY * Self::SPEED_FACTOR * Self::DT;
        self.speed *= 1.0 - Self::FRICTION;
        self.current_y += self.speed;

        // Settled when we've reached or passed the target
        if self.current_y >= self.target_y {
            return None;
        }
        Some(self.current_y)
    }
}

/// Container for all active animations in the game.
#[derive(Debug, Default)]
pub struct AnimationState {
    pub rotate_anims: Vec<RotateAnim>,
    pub fall_anims: Vec<FallAnim>,
    pub freeze_timer: f32,  // seconds remaining in freeze
}

impl AnimationState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns true if any rotation animations are still playing.
    pub fn has_rotate_anims(&self) -> bool {
        !self.rotate_anims.is_empty()
    }

    /// Returns true if any fall animations are still playing.
    pub fn has_fall_anims(&self) -> bool {
        !self.fall_anims.is_empty()
    }

    /// Returns true if the freeze timer is active.
    pub fn is_frozen(&self) -> bool {
        self.freeze_timer > 0.0
    }

    /// Advance all rotation animations. Remove completed ones.
    pub fn tick_rotations(&mut self, dt: f32) {
        self.rotate_anims.retain_mut(|anim| anim.tick(dt).is_some());
    }

    /// Advance all fall animations. Remove completed ones.
    pub fn tick_falls(&mut self) {
        self.fall_anims.retain_mut(|anim| anim.tick().is_some());
    }

    /// Advance freeze timer. Returns true if freeze just ended.
    pub fn tick_freeze(&mut self, dt: f32) -> bool {
        if self.freeze_timer > 0.0 {
            self.freeze_timer -= dt;
            if self.freeze_timer <= 0.0 {
                self.freeze_timer = 0.0;
                return true;
            }
        }
        false
    }

    /// Get the current rotation override for a tile at (x, y), if any.
    pub fn get_rotation(&self, x: usize, y: usize) -> Option<f32> {
        for anim in &self.rotate_anims {
            if anim.x == x && anim.y == y {
                let t = anim.progress;
                return Some(anim.start_rotation + (anim.end_rotation - anim.start_rotation) * t);
            }
        }
        None
    }

    /// Get the current Y override for a tile at (x, y), if any.
    pub fn get_fall_y(&self, x: usize, y: usize) -> Option<f32> {
        for anim in &self.fall_anims {
            if anim.x == x && anim.y == y {
                return Some(anim.current_y);
            }
        }
        None
    }

    /// Clear all animations.
    pub fn clear(&mut self) {
        self.rotate_anims.clear();
        self.fall_anims.clear();
        self.freeze_timer = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rotate_anim_completes() {
        let mut anim = RotateAnim::new(5, 5, 1);
        // Should be active initially
        assert!(anim.tick(0.1).is_some());
        // Should complete after 0.2s total
        assert!(anim.tick(0.11).is_none());
    }

    #[test]
    fn rotate_anim_interpolates() {
        let mut anim = RotateAnim::new(0, 0, 1);
        let rot = anim.tick(0.1).unwrap(); // 50% progress
        // Should be halfway between +PI/2 and 0
        let expected = FRAC_PI_2 * 0.5;
        assert!((rot - expected).abs() < 0.01, "got {}, expected {}", rot, expected);
    }

    #[test]
    fn fall_anim_reaches_target() {
        let mut anim = FallAnim::new(0, 0, 0.0, 100.0);
        let mut frames = 0;
        loop {
            if anim.tick().is_none() {
                break;
            }
            frames += 1;
            if frames > 600 {
                panic!("fall anim didn't settle after 600 frames");
            }
        }
        assert!(frames > 0, "should take at least 1 frame");
    }

    #[test]
    fn animation_state_tick_rotations() {
        let mut state = AnimationState::new();
        state.rotate_anims.push(RotateAnim::new(1, 2, 1));
        state.rotate_anims.push(RotateAnim::new(3, 4, 1));
        assert!(state.has_rotate_anims());

        // Tick past completion
        state.tick_rotations(0.3);
        assert!(!state.has_rotate_anims());
    }

    #[test]
    fn freeze_timer_expires() {
        let mut state = AnimationState::new();
        state.freeze_timer = 1.0;
        assert!(state.is_frozen());

        let ended = state.tick_freeze(0.5);
        assert!(!ended);
        assert!(state.is_frozen());

        let ended = state.tick_freeze(0.6);
        assert!(ended);
        assert!(!state.is_frozen());
    }
}
