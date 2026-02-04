/// Direction flags for tile connections.
/// Uses a 4-bit bitmask: right=1, up=2, left=4, down=8.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Direction(pub u8);

impl Direction {
    pub const RIGHT: Direction = Direction(1 << 0); // 0001
    pub const UP: Direction = Direction(1 << 1);    // 0010
    pub const LEFT: Direction = Direction(1 << 2);  // 0100
    pub const DOWN: Direction = Direction(1 << 3);  // 1000

    /// The opposite direction (for checking mutual connections).
    pub fn opposite(self) -> Direction {
        match self {
            d if d == Self::RIGHT => Self::LEFT,
            d if d == Self::LEFT => Self::RIGHT,
            d if d == Self::UP => Self::DOWN,
            d if d == Self::DOWN => Self::UP,
            _ => Direction(0),
        }
    }
}

/// Marking state for each tile during connection checking.
/// Maps to the Swift `Connection` enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum Marking {
    Left = 0,
    Right = 1,
    Ok = 2,
    None = 3,
    Animating = 4,
}

/// Game mode selection.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum GameMode {
    Zen = 0,   // Single player, combined score, endless
    VsBot = 1, // Player vs bot, separate scores, first to 100
}

/// Default grid dimensions matching the legacy game.
pub const DEFAULT_WIDTH: usize = 12;
pub const DEFAULT_HEIGHT: usize = 10;
pub const DEFAULT_MISSING_LINKS: usize = 3;

/// Sound events that the simulation emits for the host to play.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum SoundEvent {
    Rotate = 0,
    Explode = 1,
    Bomb = 2,
    CoinDrop = 3,
    PowerUp = 4,
    Bop = 5,
    Buzz = 6,
    Nope = 7,
}

/// Atlas column lookup: maps connection bitmask (0-15) to the correct texture atlas column.
/// From legacy GameManager.swift:97 `grid_codep`.
pub const GRID_CODEP: [u8; 16] = [0, 12, 15, 5, 14, 1, 4, 7, 13, 6, 2, 8, 3, 9, 10, 11];

/// Atlas row constants for the base_tiles texture (16x8 grid).
pub const ATLAS_ROW_NORMAL: f32 = 1.0;    // row 1: standard game tiles
pub const ATLAS_ROW_PINS: f32 = 3.0;      // row 3: left/right pins
pub const ATLAS_COL_LEFT_PIN: f32 = 12.0;  // column 12: left pin sprite
pub const ATLAS_COL_RIGHT_PIN: f32 = 14.0; // column 14: right pin sprite

/// Bonus coin types with point values.
/// UV coordinates reference the base_tiles atlas (8x8 subdivision within the 16x8 atlas).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum BonusType {
    Coin1 = 0,  // 1 point, alpha=1.5
    Coin2 = 1,  // 2 points, alpha=2.0
    Coin5 = 2,  // 5 points, alpha=3.5
}

impl BonusType {
    pub fn points(self) -> i32 {
        match self {
            BonusType::Coin1 => 1,
            BonusType::Coin2 => 2,
            BonusType::Coin5 => 5,
        }
    }

    pub fn alpha(self) -> f32 {
        match self {
            BonusType::Coin1 => 1.0,
            BonusType::Coin2 => 1.1,
            BonusType::Coin5 => 1.3,
        }
    }

    /// Atlas UV as (col, row) in the 8×8 arrows.png atlas.
    /// Legacy: all coins are in column 3, rows 2-4.
    pub fn atlas_uv(self) -> (f32, f32) {
        match self {
            BonusType::Coin1 => (3.0, 2.0),
            BonusType::Coin2 => (3.0, 3.0),
            BonusType::Coin5 => (3.0, 4.0),
        }
    }
}

/// Power-up types that players can collect and arm.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum PowerUpType {
    Bomb = 0,   // 5x5 area clear
    Cross = 1,  // Set tile to 0x0F (full connections)
    Arrow = 2,  // Clear entire column
}

impl PowerUpType {
    /// Atlas UV for the power-up sprite in the 8×8 arrows.png atlas.
    pub fn atlas_uv(self) -> (f32, f32) {
        match self {
            PowerUpType::Bomb => (7.0, 1.0),
            PowerUpType::Cross => (6.0, 0.0),
            PowerUpType::Arrow => (7.0, 0.0),
        }
    }

    /// Drop probability denominator. E.g. Bomb = 1/5 chance.
    pub fn drop_freq(self) -> u32 {
        match self {
            PowerUpType::Bomb => 5,
            PowerUpType::Cross => 3,
            PowerUpType::Arrow => 8,
        }
    }

    pub fn alpha(self) -> f32 {
        1.3
    }

    pub fn scale(self) -> f32 {
        match self {
            PowerUpType::Bomb => 0.8,
            PowerUpType::Cross | PowerUpType::Arrow => 0.7,
        }
    }

    pub fn rotation_speed(self) -> f32 {
        match self {
            PowerUpType::Bomb => 0.0,
            PowerUpType::Cross => 1.55,
            PowerUpType::Arrow => 0.95,
        }
    }
}

/// Power-up inventory for one player side (left or right).
#[derive(Debug, Clone, Default)]
pub struct PowerUpInventory {
    pub has_bomb: bool,
    pub has_cross: bool,
    pub has_arrow: bool,
    pub armed: Option<PowerUpType>,
}

impl PowerUpInventory {
    /// Toggle arming a power-up. Returns true if newly armed.
    pub fn toggle_arm(&mut self, ptype: PowerUpType) -> bool {
        let has = match ptype {
            PowerUpType::Bomb => self.has_bomb,
            PowerUpType::Cross => self.has_cross,
            PowerUpType::Arrow => self.has_arrow,
        };
        if !has {
            return false;
        }
        if self.armed == Some(ptype) {
            self.armed = None;
            false
        } else {
            self.armed = Some(ptype);
            true
        }
    }

    /// Consume the armed power-up.
    pub fn consume_armed(&mut self) -> Option<PowerUpType> {
        if let Some(ptype) = self.armed.take() {
            match ptype {
                PowerUpType::Bomb => self.has_bomb = false,
                PowerUpType::Cross => self.has_cross = false,
                PowerUpType::Arrow => self.has_arrow = false,
            }
            Some(ptype)
        } else {
            None
        }
    }
}
