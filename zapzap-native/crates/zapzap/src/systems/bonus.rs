use crate::components::{BonusType, Marking, PowerUpType};
use crate::systems::board::{GameBoard, Rng};

/// A falling bonus object (coin or power-up).
#[derive(Debug, Clone)]
pub struct FallingBonus {
    pub tile_x: usize,
    pub tile_y: usize,
    pub current_y: f32,
    pub target_y: f32,
    pub speed: f32,
    pub scale: f32,
    pub rotation: f32,
    pub kind: FallingBonusKind,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum FallingBonusKind {
    Coin(BonusType),
    PowerUp(PowerUpType),
}

impl FallingBonus {
    const GRAVITY: f32 = 9.8;
    const FRICTION: f32 = 0.005;
    const DT: f32 = 1.0 / 60.0;

    pub fn new(
        tile_x: usize,
        tile_y: usize,
        start_y: f32,
        target_y: f32,
        kind: FallingBonusKind,
    ) -> Self {
        let board_h = 500.0; // approx 10 * 50
        let tile_size = 50.0;
        let initial_scale = 1.0 + 0.3 * (board_h / tile_size);
        FallingBonus {
            tile_x,
            tile_y,
            current_y: start_y,
            target_y,
            speed: 0.0,
            scale: initial_scale,
            rotation: 0.0,
            kind,
        }
    }

    /// Advance physics one frame. Returns true if still falling, false when landed.
    pub fn tick(&mut self) -> bool {
        self.speed += Self::GRAVITY * Self::DT;
        self.speed *= 1.0 - Self::FRICTION;
        self.current_y += self.speed;

        // Shrink scale as it approaches target
        let tile_size = 50.0;
        let dist = (self.target_y - self.current_y).max(0.0);
        self.scale = 1.0 + 0.5 * dist / tile_size;
        if self.scale < 1.0 {
            self.scale = 1.0;
        }

        // Rotation for power-ups
        if let FallingBonusKind::PowerUp(ptype) = self.kind {
            self.rotation += ptype.rotation_speed() * Self::DT;
        }

        if self.current_y >= self.target_y {
            self.current_y = self.target_y;
            self.scale = 1.0;
            return false;
        }
        true
    }

    pub fn alpha(&self) -> f32 {
        match self.kind {
            FallingBonusKind::Coin(c) => c.alpha(),
            FallingBonusKind::PowerUp(p) => p.alpha(),
        }
    }

    pub fn base_scale(&self) -> f32 {
        match self.kind {
            FallingBonusKind::Coin(_) => 0.8,
            FallingBonusKind::PowerUp(p) => p.scale(),
        }
    }

    pub fn atlas_uv(&self) -> (f32, f32) {
        match self.kind {
            FallingBonusKind::Coin(c) => c.atlas_uv(),
            FallingBonusKind::PowerUp(p) => p.atlas_uv(),
        }
    }

    pub fn points(&self) -> i32 {
        match self.kind {
            FallingBonusKind::Coin(c) => c.points(),
            FallingBonusKind::PowerUp(_) => 0,
        }
    }
}

/// Calculate bonus coin drops based on pin connections.
/// Returns (many1, many2, many5).
pub fn calculate_bonus_drops(left_pins: usize, right_pins: usize) -> (usize, usize, usize) {
    let mut many1s: usize = 2; // Always start with 2 base coins
    let mut many2s: usize = 0;
    let mut many5s: usize = 0;

    // Left side bonus
    if left_pins > 6 {
        many1s += 1;
        many2s += 3;
        many5s += left_pins - 6;
    } else if left_pins > 3 {
        many1s += 1;
        many2s += left_pins - 3;
    }

    // Right side bonus
    if right_pins > 6 {
        many1s += 1;
        many2s += 3;
        many5s += right_pins - 6;
    } else if right_pins > 3 {
        many1s += 1;
        many2s += right_pins - 3;
    }

    (many1s, many2s, many5s)
}

/// Container for all falling bonus objects and landed (collectible) bonuses.
#[derive(Debug, Default)]
pub struct BonusState {
    pub falling: Vec<FallingBonus>,
    pub landed: Vec<FallingBonus>,
}

impl BonusState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Create falling bonus objects from the calculated coin counts and random power-ups.
    pub fn spawn_bonuses(
        &mut self,
        many1: usize,
        many2: usize,
        many5: usize,
        board: &GameBoard,
        rng: &mut Rng,
        tile_size: f32,
        _offset_x: f32,
        offset_y: f32,
    ) {
        self.falling.clear();
        self.landed.clear();

        let mut occupied: Vec<(usize, usize)> = Vec::new();

        let mut spawn = |kind: FallingBonusKind, rng: &mut Rng, occupied: &mut Vec<(usize, usize)>| {
            // Pick a random unoccupied tile
            let mut attempts = 0;
            let (rx, ry) = loop {
                let rx = rng.next_int(board.width as u32) as usize;
                let ry = rng.next_int(board.height as u32) as usize;
                if !occupied.contains(&(rx, ry)) || attempts > 50 {
                    break (rx, ry);
                }
                attempts += 1;
            };
            occupied.push((rx, ry));

            let target_y = offset_y + ry as f32 * tile_size + tile_size * 0.5;
            let start_y = target_y - (board.height as f32) * tile_size * 0.5;
            self.falling.push(FallingBonus::new(rx, ry, start_y, target_y, kind));
        };

        for _ in 0..many1 {
            spawn(FallingBonusKind::Coin(BonusType::Coin1), rng, &mut occupied);
        }
        for _ in 0..many2 {
            spawn(FallingBonusKind::Coin(BonusType::Coin2), rng, &mut occupied);
        }
        for _ in 0..many5 {
            spawn(FallingBonusKind::Coin(BonusType::Coin5), rng, &mut occupied);
        }

        // Random power-up drops
        for ptype in [PowerUpType::Bomb, PowerUpType::Cross, PowerUpType::Arrow] {
            if rng.next_int(ptype.drop_freq()) == 0 {
                spawn(FallingBonusKind::PowerUp(ptype), rng, &mut occupied);
            }
        }
    }

    /// Advance all falling bonuses. Returns true if any are still falling.
    pub fn tick_falling(&mut self) -> bool {
        let mut still_falling = Vec::new();
        for mut bonus in self.falling.drain(..) {
            if bonus.tick() {
                still_falling.push(bonus);
            } else {
                self.landed.push(bonus);
            }
        }
        self.falling = still_falling;
        !self.falling.is_empty()
    }

    /// Collect landed bonuses based on tile markings.
    /// Returns (left_points, right_points, collected_power_ups_for_left, collected_power_ups_for_right).
    pub fn collect_landed(
        &mut self,
        board: &GameBoard,
    ) -> (i32, i32, Vec<PowerUpType>, Vec<PowerUpType>) {
        let mut left_pts = 0;
        let mut right_pts = 0;
        let mut left_powers = Vec::new();
        let mut right_powers = Vec::new();
        let mut remaining = Vec::new();

        for bonus in self.landed.drain(..) {
            let marking = board.get_marking(bonus.tile_x, bonus.tile_y);
            match marking {
                Marking::Left | Marking::Ok => {
                    left_pts += bonus.points();
                    if let FallingBonusKind::PowerUp(ptype) = bonus.kind {
                        left_powers.push(ptype);
                    }
                }
                Marking::Right => {
                    right_pts += bonus.points();
                    if let FallingBonusKind::PowerUp(ptype) = bonus.kind {
                        right_powers.push(ptype);
                    }
                }
                _ => {
                    // Not on a marked tile — bonus not collected
                    remaining.push(bonus);
                }
            }
        }

        self.landed = remaining;
        (left_pts, right_pts, left_powers, right_powers)
    }

    /// All bonuses (falling + landed) for rendering.
    pub fn all_bonuses(&self) -> impl Iterator<Item = &FallingBonus> {
        self.falling.iter().chain(self.landed.iter())
    }

    /// Clear all bonuses.
    pub fn clear(&mut self) {
        self.falling.clear();
        self.landed.clear();
    }

    pub fn is_empty(&self) -> bool {
        self.falling.is_empty() && self.landed.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bonus_drop_calculation_base() {
        let (m1, m2, m5) = calculate_bonus_drops(0, 0);
        assert_eq!((m1, m2, m5), (2, 0, 0)); // just base coins
    }

    #[test]
    fn bonus_drop_calculation_medium() {
        let (m1, m2, m5) = calculate_bonus_drops(5, 0);
        assert_eq!(m1, 3); // 2 base + 1
        assert_eq!(m2, 2); // 5-3
        assert_eq!(m5, 0);
    }

    #[test]
    fn bonus_drop_calculation_high() {
        let (m1, m2, m5) = calculate_bonus_drops(8, 9);
        // Left: 8 > 6 → +1, +3, +(8-6)=2
        // Right: 9 > 6 → +1, +3, +(9-6)=3
        assert_eq!(m1, 4); // 2 + 1 + 1
        assert_eq!(m2, 6); // 3 + 3
        assert_eq!(m5, 5); // 2 + 3
    }

    #[test]
    fn falling_bonus_lands() {
        let mut bonus = FallingBonus::new(
            3, 5, 0.0, 300.0,
            FallingBonusKind::Coin(BonusType::Coin1),
        );
        let mut frames = 0;
        while bonus.tick() {
            frames += 1;
            if frames > 600 {
                panic!("bonus didn't land");
            }
        }
        assert!(frames > 0);
        assert!((bonus.current_y - 300.0).abs() < 0.01);
    }

    #[test]
    fn bonus_state_spawns_and_ticks() {
        let board = GameBoard::new(12, 10, 30, 42);
        let mut rng = Rng::new(123);
        let mut state = BonusState::new();
        state.spawn_bonuses(2, 1, 0, &board, &mut rng, 50.0, 150.0, 25.0);
        assert!(state.falling.len() >= 3); // at least 3 coins + possibly power-ups

        // Tick until all land
        let mut frames = 0;
        while state.tick_falling() {
            frames += 1;
            if frames > 600 {
                panic!("bonuses didn't all land");
            }
        }
        assert!(state.falling.is_empty());
        assert!(!state.landed.is_empty());
    }
}
