use crate::components::{Direction, Marking};
use crate::systems::board::GameBoard;

/// The AI player that evaluates all possible single-tile rotations
/// and picks the one that yields the highest connection score.
pub struct BotPlayer;

/// A move recommendation: which tile to rotate and how many times.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BotMove {
    pub x: usize,
    pub y: usize,
    pub rotation_count: usize,
}

impl BotPlayer {
    /// Find the best single-tile rotation on the board.
    /// Returns `None` if no move improves the score.
    pub fn determine_next_move(board: &GameBoard) -> Option<BotMove> {
        let mut best_move: Option<BotMove> = None;
        let mut best_score: i32 = 0;

        for x in 0..board.width {
            for y in 0..board.height {
                let tile = match board.grid.get(x, y) {
                    Some(t) => *t,
                    None => continue,
                };

                // Skip tiles that can't meaningfully rotate:
                // single-connection (1,2,4,8) or full-connection (15)
                if matches!(tile.connections, 1 | 2 | 4 | 8 | 15) {
                    continue;
                }

                // Try up to 3 rotations
                let mut sim = board.clone();
                for rot in 1..=3 {
                    if let Some(t) = sim.grid.get_mut(x, y) {
                        t.rotate();
                    }

                    let score = Self::evaluate_connections(&mut sim);
                    if score > best_score {
                        best_score = score;
                        best_move = Some(BotMove {
                            x,
                            y,
                            rotation_count: rot,
                        });
                    }
                }
            }
        }

        best_move
    }

    /// Evaluate the current board state.
    /// If a full left-right connection exists, score = 2 × number of Ok tiles.
    /// Otherwise, score = count of Right-marked tiles + bonus for right-edge pins.
    fn evaluate_connections(board: &mut GameBoard) -> i32 {
        let mut score: i32 = 0;
        let zap = board.check_connections();

        if zap != 0 {
            // Full connection: count Ok tiles × 2
            for j in 0..board.height {
                for i in 0..board.width {
                    if board.get_marking(i, j) == Marking::Ok {
                        score += 2;
                    }
                }
            }
        } else {
            // Partial: count tiles reachable from right
            for j in 0..board.height {
                for i in 0..board.width {
                    if board.get_marking(i, j) == Marking::Right {
                        score += 1;
                        // Bonus for right-edge pin connections
                        if i == board.width - 1 {
                            if let Some(t) = board.grid.get(i, j) {
                                if t.has_connection(Direction::RIGHT) {
                                    score += 3;
                                }
                            }
                        }
                    }
                }
            }
        }

        score
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::grid::Tile;

    #[test]
    fn bot_finds_completing_move() {
        // Set up a 3x1 board that's *almost* connected.
        // Col 0: LEFT+RIGHT, Col 1: UP+DOWN (blocking), Col 2: LEFT+RIGHT
        // Rotating Col 1 once gives LEFT+RIGHT -> connection!
        let mut board = GameBoard::new(3, 1, 0, 1);
        board.grid.set(0, 0, Some(Tile::new(0b0101))); // LEFT+RIGHT
        board.grid.set(1, 0, Some(Tile::new(0b1010))); // UP+DOWN (needs rotate to LEFT+RIGHT)
        board.grid.set(2, 0, Some(Tile::new(0b0101))); // LEFT+RIGHT

        let bot_move = BotPlayer::determine_next_move(&board);
        assert!(bot_move.is_some(), "bot should find a move");

        let m = bot_move.unwrap();
        assert_eq!(m.x, 1, "should rotate the middle tile");
        assert_eq!(m.y, 0);
        assert_eq!(m.rotation_count, 1, "one rotation turns UP+DOWN into LEFT+RIGHT");
    }

    #[test]
    fn bot_returns_none_for_no_improvement() {
        // All tiles are dead ends pointing up — no rotation helps
        let mut board = GameBoard::new(3, 1, 0, 1);
        board.grid.set(0, 0, Some(Tile::new(0b0010))); // UP
        board.grid.set(1, 0, Some(Tile::new(0b0010))); // UP
        board.grid.set(2, 0, Some(Tile::new(0b0010))); // UP

        let bot_move = BotPlayer::determine_next_move(&board);
        assert!(bot_move.is_none(), "no useful move for single-connection tiles");
    }

    #[test]
    fn bot_prefers_zap_over_partial() {
        // 4x1 board. Two possible rotations:
        // - Rotating (1,0) to complete the path (zap, high score)
        // - Rotating (3,0) also gives partial connections
        // Bot should pick the completing move.
        let mut board = GameBoard::new(4, 1, 0, 1);
        board.grid.set(0, 0, Some(Tile::new(0b0101))); // L+R
        board.grid.set(1, 0, Some(Tile::new(0b1010))); // U+D (rotate -> L+R)
        board.grid.set(2, 0, Some(Tile::new(0b0101))); // L+R
        board.grid.set(3, 0, Some(Tile::new(0b0101))); // L+R

        let bot_move = BotPlayer::determine_next_move(&board);
        assert!(bot_move.is_some());
        let m = bot_move.unwrap();
        // The bot should pick tile (1,0) since completing the path scores higher
        assert_eq!(m.x, 1);
        assert_eq!(m.rotation_count, 1);
    }
}
