use std::collections::VecDeque;

use crate::components::{Direction, Marking, DEFAULT_HEIGHT, DEFAULT_MISSING_LINKS, DEFAULT_WIDTH};
use crate::grid::{Grid, Tile};

/// Seedable pseudo-random number generator (xorshift64).
/// Deterministic, fast, no-std compatible.
#[derive(Debug, Clone)]
pub struct Rng {
    state: u64,
}

impl Rng {
    pub fn new(seed: u64) -> Self {
        // Avoid zero state
        Rng {
            state: if seed == 0 { 1 } else { seed },
        }
    }

    /// Generate next u64 using xorshift64.
    fn next_u64(&mut self) -> u64 {
        let mut x = self.state;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.state = x;
        x
    }

    /// Generate a random number in [0, upper_bound).
    pub fn next_int(&mut self, upper_bound: u32) -> u32 {
        (self.next_u64() % upper_bound as u64) as u32
    }
}

/// The core game board, equivalent to Swift's `GameBoard`.
#[derive(Debug, Clone)]
pub struct GameBoard {
    pub width: usize,
    pub height: usize,
    pub grid: Grid,
    pub markings: Vec<Marking>, // flat: width * height, column-major
    pub multiplier_left: Vec<i32>,
    pub multiplier_right: Vec<i32>,
    pub rng: Rng,

    pub left_pins_connect: usize,
    pub right_pins_connect: usize,
    pub left_conquered: usize,
    pub right_conquered: usize,

    missing_links: usize, // percentage
    new_elements: usize,
    missing_link_elements: usize,
}

impl GameBoard {
    /// Create a new board with random tiles.
    pub fn new(width: usize, height: usize, missing_links: usize, seed: u64) -> Self {
        let mut board = GameBoard {
            width,
            height,
            grid: Grid::new(width, height),
            markings: vec![Marking::None; width * height],
            multiplier_left: vec![1; height],
            multiplier_right: vec![1; height],
            rng: Rng::new(seed),
            left_pins_connect: 0,
            right_pins_connect: 0,
            left_conquered: 0,
            right_conquered: 0,
            missing_links,
            new_elements: 0,
            missing_link_elements: 0,
        };
        board.reset_table(missing_links);
        board
    }

    /// Create a default 12x10 board.
    pub fn new_default(seed: u64) -> Self {
        Self::new(DEFAULT_WIDTH, DEFAULT_HEIGHT, DEFAULT_MISSING_LINKS, seed)
    }

    #[inline]
    fn marking_idx(&self, x: usize, y: usize) -> usize {
        x * self.height + y
    }

    pub fn get_marking(&self, x: usize, y: usize) -> Marking {
        self.markings[self.marking_idx(x, y)]
    }

    pub fn set_marking(&mut self, x: usize, y: usize, m: Marking) {
        let i = self.marking_idx(x, y);
        self.markings[i] = m;
    }

    /// Set a tile's connections at position (x, y).
    pub fn set_tile(&mut self, x: usize, y: usize, connection: u8) {
        if let Some(tile) = self.grid.get_mut(x, y) {
            tile.connections = connection & 0x0F;
        }
    }

    /// Generate a random tile connection value (1..=15).
    /// Controls the ratio of "dead-end" tiles (single connections).
    pub fn get_new_element(&mut self) -> u8 {
        let mut k = (self.rng.next_int(15) + 1) as u8;
        self.new_elements += 1;

        // If too many dead-ends, reroll until we get a multi-connection tile
        if self.new_elements > 0
            && (100 * self.missing_link_elements / self.new_elements) > self.missing_links
        {
            while matches!(k, 1 | 2 | 4 | 8) {
                k = (self.rng.next_int(15) + 1) as u8;
            }
        }

        if matches!(k, 1 | 2 | 4 | 8) {
            self.missing_link_elements += 1;
        }

        k
    }

    /// Reset the entire board with fresh random tiles.
    pub fn reset_table(&mut self, percent_missing_links: usize) {
        self.missing_links = percent_missing_links;
        self.new_elements = 0;
        self.missing_link_elements = 0;

        for j in 0..self.height {
            for i in 0..self.width {
                let conn = self.get_new_element();
                self.grid.set(i, j, Some(Tile::new(conn)));
                self.set_marking(i, j, Marking::None);
            }
            self.multiplier_left[j] = 1;
            self.multiplier_right[j] = 1;
        }
    }

    // -----------------------------------------------------------------------
    // ITERATIVE BFS FLOOD-FILL — replaces Swift's recursive expandConnectionsMarkings
    // -----------------------------------------------------------------------

    /// Iterative BFS flood-fill that marks connected tiles starting from a seed.
    /// `cx, cy` — starting position.
    /// `incoming_dir` — the direction from which the connection enters (e.g., RIGHT means
    ///   we're checking if this tile accepts a connection from the right side).
    /// `marker` — the Marking to apply (Left, Right, or Ok).
    fn expand_connections_bfs(&mut self, cx: usize, cy: usize, incoming_dir: Direction, marker: Marking) {
        // Only allow Left, Right, Ok markers (same guard as Swift: marker <= .none)
        if marker == Marking::None || marker == Marking::Animating {
            return;
        }

        // BFS queue items: (x, y, incoming_direction)
        let mut queue: VecDeque<(usize, usize, Direction)> = VecDeque::with_capacity(self.width * self.height);
        queue.push_back((cx, cy, incoming_dir));

        while let Some((x, y, ctype)) = queue.pop_front() {
            // Bounds check
            if x >= self.width || y >= self.height {
                continue;
            }

            // Already visited with this marker? Skip.
            if self.get_marking(x, y) == marker {
                continue;
            }

            // Check the tile exists and has a connection matching the incoming direction
            let tile = match self.grid.get(x, y) {
                Some(t) if t.has_connection(ctype) => *t,
                _ => continue,
            };

            // Mark this tile
            self.set_marking(x, y, marker);

            // Explore all 4 outgoing directions from this tile
            // For each direction, we push the neighbor with the *opposite* direction
            // (because we enter the neighbor from the opposite side).

            if tile.has_connection(Direction::LEFT) && x > 0 {
                queue.push_back((x - 1, y, Direction::RIGHT));
            }
            if tile.has_connection(Direction::UP) && y > 0 {
                queue.push_back((x, y - 1, Direction::DOWN));
            }
            if tile.has_connection(Direction::RIGHT) {
                queue.push_back((x + 1, y, Direction::LEFT));
            }
            if tile.has_connection(Direction::DOWN) {
                queue.push_back((x, y + 1, Direction::UP));
            }
        }
    }

    /// Check connections from both sides of the board.
    /// Returns 1 if any left-to-right connection is found, 0 otherwise.
    /// Also updates `left_pins_connect` and `right_pins_connect`.
    pub fn check_connections(&mut self) -> i32 {
        let mut result = 0;
        self.left_pins_connect = 0;
        self.right_pins_connect = 0;

        // Reset markings (preserve Animating)
        for j in 0..self.height {
            for i in 0..self.width {
                if self.get_marking(i, j) != Marking::Animating {
                    self.set_marking(i, j, Marking::None);
                }
            }
        }

        // Pass 1: Flood-fill from right edge (column width-1)
        for j in 0..self.height {
            if let Some(tile) = self.grid.get(self.width - 1, j) {
                if tile.has_connection(Direction::RIGHT) {
                    self.expand_connections_bfs(self.width - 1, j, Direction::RIGHT, Marking::Right);
                }
            }
        }

        // Pass 2: Flood-fill from left edge (column 0)
        for j in 0..self.height {
            if let Some(tile) = self.grid.get(0, j) {
                if tile.has_connection(Direction::LEFT) {
                    // If this tile was already reached from the right, upgrade to Ok
                    let marker = if self.get_marking(0, j) == Marking::Right
                        || self.get_marking(0, j) == Marking::Ok
                    {
                        Marking::Ok
                    } else {
                        Marking::Left
                    };
                    self.expand_connections_bfs(0, j, Direction::LEFT, marker);
                }
            }
        }

        // Pass 3: Count connecting pins
        for j in 0..self.height {
            if let Some(tile) = self.grid.get(0, j) {
                if tile.has_connection(Direction::LEFT) && self.get_marking(0, j) == Marking::Ok {
                    result = 1;
                    self.left_pins_connect += 1;
                }
            }
            if let Some(tile) = self.grid.get(self.width - 1, j) {
                if tile.has_connection(Direction::RIGHT)
                    && self.get_marking(self.width - 1, j) == Marking::Ok
                {
                    self.right_pins_connect += 1;
                }
            }
        }

        result
    }

    /// Remove tiles marked as Ok and shift remaining tiles down (gravity).
    /// New random tiles fill in from the top.
    ///
    /// Algorithm: for each column, collect non-Ok tiles bottom-up, then
    /// place them at the bottom and fill the remaining top slots with new tiles.
    pub fn remove_and_shift_connecting_tiles(&mut self) {
        for x in 0..self.width {
            // Collect surviving tiles (non-Ok), preserving bottom-up order
            let mut survivors: Vec<Tile> = Vec::with_capacity(self.height);
            for y in (0..self.height).rev() {
                if self.get_marking(x, y) != Marking::Ok {
                    if let Some(tile) = self.grid.get(x, y) {
                        survivors.push(*tile);
                    }
                }
            }

            // Place survivors at the bottom (reversed so bottom-most stays bottom)
            let num_new = self.height - survivors.len();
            for (i, tile) in survivors.into_iter().enumerate() {
                let y = self.height - 1 - i;
                self.grid.set(x, y, Some(tile));
            }

            // Fill the top with new random tiles
            for y in 0..num_new {
                let conn = self.get_new_element();
                self.grid.set(x, y, Some(Tile::new(conn)));
            }
        }
    }

    /// Bomb (power-up): remove tiles in a rectangle around (ati, atj) and shift down.
    pub fn bomb_table(&mut self, ati: usize, atj: usize, delta_x: usize, delta_y: usize) {
        if ati >= self.width || atj >= self.height {
            return;
        }

        let start_i = ati.saturating_sub(delta_x);
        let end_i = (ati + delta_x + 1).min(self.width);
        let start_j = atj.saturating_sub(delta_y);
        let end_j = (atj + delta_y + 1).min(self.height);

        for x in start_i..end_i {
            let mut shifted = 0;
            for y in (start_j..end_j).rev() {
                if y >= 1 {
                    for shift_y in (1..=y).rev() {
                        self.grid.copy_within_column(
                            x,
                            shift_y + shifted - 1,
                            shift_y + shifted,
                        );
                    }
                }
                let conn = self.get_new_element();
                self.grid.set(x, 0, Some(Tile::new(conn)));
                shifted += 1;
            }
            for fill_y in (0..shifted).rev() {
                let conn = self.get_new_element();
                self.grid.set(x, fill_y, Some(Tile::new(conn)));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rng_deterministic() {
        let mut a = Rng::new(42);
        let mut b = Rng::new(42);
        for _ in 0..100 {
            assert_eq!(a.next_int(100), b.next_int(100));
        }
    }

    #[test]
    fn rng_range() {
        let mut rng = Rng::new(12345);
        for _ in 0..1000 {
            let v = rng.next_int(15);
            assert!(v < 15);
        }
    }

    #[test]
    fn new_element_range() {
        let mut board = GameBoard::new(12, 10, 30, 42);
        for _ in 0..500 {
            let e = board.get_new_element();
            assert!(e >= 1 && e <= 15, "got {}", e);
        }
    }

    #[test]
    fn board_initializes_all_tiles() {
        let board = GameBoard::new(12, 10, 30, 42);
        for x in 0..12 {
            for y in 0..10 {
                assert!(board.grid.get(x, y).is_some(), "tile at ({},{}) is None", x, y);
            }
        }
    }

    /// Build a simple 3-wide board where all tiles connect left-to-right.
    /// Layout (3x1):
    ///   Col 0: LEFT+RIGHT (0b0101 = 5) — connects to left pin and right neighbor
    ///   Col 1: LEFT+RIGHT (0b0101 = 5) — bridge
    ///   Col 2: LEFT+RIGHT (0b0101 = 5) — connects to right pin and left neighbor
    #[test]
    fn check_connections_simple_horizontal() {
        let mut board = GameBoard::new(3, 1, 0, 1);
        // Manually set tiles
        board.grid.set(0, 0, Some(Tile::new(0b0101))); // LEFT + RIGHT
        board.grid.set(1, 0, Some(Tile::new(0b0101))); // LEFT + RIGHT
        board.grid.set(2, 0, Some(Tile::new(0b0101))); // LEFT + RIGHT

        let result = board.check_connections();
        assert_eq!(result, 1, "should detect a left-to-right connection");
        assert_eq!(board.left_pins_connect, 1);
        assert_eq!(board.right_pins_connect, 1);

        // All tiles should be marked Ok
        assert_eq!(board.get_marking(0, 0), Marking::Ok);
        assert_eq!(board.get_marking(1, 0), Marking::Ok);
        assert_eq!(board.get_marking(2, 0), Marking::Ok);
    }

    /// Board with no connection path.
    #[test]
    fn check_connections_no_path() {
        let mut board = GameBoard::new(3, 1, 0, 1);
        board.grid.set(0, 0, Some(Tile::new(0b0100))); // LEFT only
        board.grid.set(1, 0, Some(Tile::new(0b1000))); // DOWN only - blocks path
        board.grid.set(2, 0, Some(Tile::new(0b0001))); // RIGHT only

        let result = board.check_connections();
        assert_eq!(result, 0, "no connection should be found");
        assert_eq!(board.left_pins_connect, 0);
        assert_eq!(board.right_pins_connect, 0);
    }

    /// L-shaped path through a 3x2 board.
    ///
    /// ```text
    ///   Col 0    Col 1    Col 2
    /// Row 0: L+R(5)  L+D(12)   --(8)
    /// Row 1:  --(2)  U+R(3)   L+R(5)
    /// ```
    /// Path: (0,0) -right-> (1,0) -down-> (1,1) -right-> (2,1) -right pin
    /// And left pin at (0,0)
    #[test]
    fn check_connections_l_shaped_path() {
        let mut board = GameBoard::new(3, 2, 0, 1);

        // Row 0
        board.grid.set(0, 0, Some(Tile::new(0b0101))); // LEFT + RIGHT
        board.grid.set(1, 0, Some(Tile::new(0b1100))); // LEFT + DOWN
        board.grid.set(2, 0, Some(Tile::new(0b1000))); // DOWN only (dead end, no right pin)

        // Row 1
        board.grid.set(0, 1, Some(Tile::new(0b0010))); // UP only
        board.grid.set(1, 1, Some(Tile::new(0b0011))); // RIGHT + UP
        board.grid.set(2, 1, Some(Tile::new(0b0101))); // LEFT + RIGHT

        let result = board.check_connections();
        assert_eq!(result, 1, "L-shaped path should connect");

        // The path tiles should be Ok
        assert_eq!(board.get_marking(0, 0), Marking::Ok);
        assert_eq!(board.get_marking(1, 0), Marking::Ok);
        assert_eq!(board.get_marking(1, 1), Marking::Ok);
        assert_eq!(board.get_marking(2, 1), Marking::Ok);
    }

    /// Multiple parallel horizontal paths.
    #[test]
    fn check_connections_multiple_rows() {
        let mut board = GameBoard::new(3, 3, 0, 1);

        // Row 0: full horizontal path
        board.grid.set(0, 0, Some(Tile::new(0b0101)));
        board.grid.set(1, 0, Some(Tile::new(0b0101)));
        board.grid.set(2, 0, Some(Tile::new(0b0101)));

        // Row 1: broken
        board.grid.set(0, 1, Some(Tile::new(0b0100))); // LEFT only
        board.grid.set(1, 1, Some(Tile::new(0b1000))); // DOWN only
        board.grid.set(2, 1, Some(Tile::new(0b0001))); // RIGHT only

        // Row 2: full horizontal path
        board.grid.set(0, 2, Some(Tile::new(0b0101)));
        board.grid.set(1, 2, Some(Tile::new(0b0101)));
        board.grid.set(2, 2, Some(Tile::new(0b0101)));

        let result = board.check_connections();
        assert_eq!(result, 1);
        assert_eq!(board.left_pins_connect, 2);
        assert_eq!(board.right_pins_connect, 2);
    }

    #[test]
    fn remove_and_shift_basic() {
        let mut board = GameBoard::new(3, 3, 0, 99);

        // Set up a horizontal connection in row 1
        board.grid.set(0, 1, Some(Tile::new(0b0101)));
        board.grid.set(1, 1, Some(Tile::new(0b0101)));
        board.grid.set(2, 1, Some(Tile::new(0b0101)));

        // Fill other rows with identifiable tiles
        for x in 0..3 {
            board.grid.set(x, 0, Some(Tile::new(0b1111))); // top row: all connections
            board.grid.set(x, 2, Some(Tile::new(0b0010))); // bottom row: UP only
        }

        // Check connections to mark row 1 as Ok
        let _ = board.check_connections();
        assert_eq!(board.get_marking(0, 1), Marking::Ok);

        // Remember what was in row 0 before the shift
        let old_top = board.grid.get(0, 0).unwrap().connections;

        // Remove and shift
        board.remove_and_shift_connecting_tiles();

        // Row 0's old tile should now be in row 1 (shifted down)
        // The top (row 0) should have new random tiles
        let new_at_1 = board.grid.get(0, 1).unwrap();
        assert_eq!(
            new_at_1.connections, old_top,
            "old top row should shift down to row 1"
        );

        // Row 0 should have a new tile (not None)
        assert!(board.grid.get(0, 0).is_some());
    }
}
