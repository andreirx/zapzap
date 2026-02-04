use crate::components::Direction;

/// A single tile on the board. Stores its connection bitmask in the lower 4 bits.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Tile {
    pub connections: u8,
}

impl Tile {
    pub fn new(connections: u8) -> Self {
        Tile {
            connections: connections & 0x0F,
        }
    }

    /// Rotate the tile clockwise by one step (right->down->left->up->right).
    /// Equivalent to shifting bits left by 1 within the 4-bit field.
    pub fn rotate(&mut self) {
        let mut r = self.connections << 1;
        r = (r & 0x0F) | (r >> 4);
        self.connections = r & 0x0F;
    }

    /// Check if this tile has a connection in the given direction.
    pub fn has_connection(&self, dir: Direction) -> bool {
        (self.connections & dir.0) != 0
    }

    /// Returns true if this tile is a "dead end" (only one connection bit set).
    pub fn is_single_connection(&self) -> bool {
        matches!(self.connections, 1 | 2 | 4 | 8)
    }
}

/// The board grid. Uses column-major layout: `tiles[x][y]` where x is column, y is row.
/// `None` means an empty cell.
#[derive(Debug, Clone)]
pub struct Grid {
    pub width: usize,
    pub height: usize,
    /// Flat storage in column-major order: index = x * height + y
    tiles: Vec<Option<Tile>>,
}

impl Grid {
    pub fn new(width: usize, height: usize) -> Self {
        Grid {
            width,
            height,
            tiles: vec![None; width * height],
        }
    }

    #[inline]
    fn idx(&self, x: usize, y: usize) -> usize {
        x * self.height + y
    }

    pub fn get(&self, x: usize, y: usize) -> Option<&Tile> {
        self.tiles[self.idx(x, y)].as_ref()
    }

    pub fn get_mut(&mut self, x: usize, y: usize) -> Option<&mut Tile> {
        let i = self.idx(x, y);
        self.tiles[i].as_mut()
    }

    pub fn set(&mut self, x: usize, y: usize, tile: Option<Tile>) {
        let i = self.idx(x, y);
        self.tiles[i] = tile;
    }

    /// Copy tile from one position to another within the same column.
    pub fn copy_within_column(&mut self, x: usize, from_y: usize, to_y: usize) {
        let from_i = self.idx(x, from_y);
        let to_i = self.idx(x, to_y);
        self.tiles[to_i] = self.tiles[from_i];
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tile_rotate_cycles() {
        // A tile with only RIGHT (1) should cycle: RIGHT -> DOWN -> LEFT -> UP -> RIGHT
        let mut tile = Tile::new(0b0001); // RIGHT
        assert!(tile.has_connection(Direction::RIGHT));

        tile.rotate();
        assert_eq!(tile.connections, 0b0010); // UP
        assert!(tile.has_connection(Direction::UP));

        tile.rotate();
        assert_eq!(tile.connections, 0b0100); // LEFT
        assert!(tile.has_connection(Direction::LEFT));

        tile.rotate();
        assert_eq!(tile.connections, 0b1000); // DOWN
        assert!(tile.has_connection(Direction::DOWN));

        tile.rotate();
        assert_eq!(tile.connections, 0b0001); // back to RIGHT
    }

    #[test]
    fn tile_multi_connection_rotate() {
        // RIGHT + UP = 0b0011 -> UP + LEFT = 0b0110 -> LEFT + DOWN = 0b1100 -> etc
        let mut tile = Tile::new(0b0011);
        tile.rotate();
        assert_eq!(tile.connections, 0b0110);
        tile.rotate();
        assert_eq!(tile.connections, 0b1100);
        tile.rotate();
        assert_eq!(tile.connections, 0b1001);
        tile.rotate();
        assert_eq!(tile.connections, 0b0011); // back to original
    }

    #[test]
    fn tile_masks_upper_bits() {
        let tile = Tile::new(0xFF);
        assert_eq!(tile.connections, 0x0F);
    }

    #[test]
    fn grid_get_set() {
        let mut grid = Grid::new(12, 10);
        assert!(grid.get(0, 0).is_none());

        grid.set(5, 3, Some(Tile::new(0b0101)));
        let t = grid.get(5, 3).unwrap();
        assert_eq!(t.connections, 0b0101);
        assert!(t.has_connection(Direction::RIGHT));
        assert!(t.has_connection(Direction::LEFT));
        assert!(!t.has_connection(Direction::UP));
    }
}
