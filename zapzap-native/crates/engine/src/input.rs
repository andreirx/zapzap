/// Input event types the engine understands.
/// Generic — no game-specific semantics.
#[derive(Debug, Clone, Copy)]
pub enum InputEvent {
    /// A touch/click began at screen coordinates (x, y).
    PointerDown { x: f32, y: f32 },
    /// A touch/click ended at screen coordinates (x, y).
    PointerUp { x: f32, y: f32 },
    /// A touch/cursor moved to screen coordinates (x, y).
    PointerMove { x: f32, y: f32 },
    /// A key was pressed.
    KeyDown { key_code: u32 },
    /// A key was released.
    KeyUp { key_code: u32 },
}

/// A ring buffer of input events.
/// JS writes events into the queue; Rust reads and drains them each frame.
pub struct InputQueue {
    events: Vec<InputEvent>,
}

impl InputQueue {
    pub fn new() -> Self {
        Self {
            events: Vec::with_capacity(32),
        }
    }

    /// Push a new input event (called from JS via wasm-bindgen).
    pub fn push(&mut self, event: InputEvent) {
        self.events.push(event);
    }

    /// Drain all pending events. Returns an iterator and clears the queue.
    pub fn drain(&mut self) -> Vec<InputEvent> {
        std::mem::take(&mut self.events)
    }

    /// Check if there are pending events.
    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    /// Number of pending events.
    pub fn len(&self) -> usize {
        self.events.len()
    }
}

impl Default for InputQueue {
    fn default() -> Self {
        Self::new()
    }
}
