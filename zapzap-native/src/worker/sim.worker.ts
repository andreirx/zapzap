// Simulation Web Worker — runs WASM game engine off the main thread.
// Communicates with host via SharedArrayBuffer + postMessage commands.
//
// Protocol (per DECISIONS.md):
//   SharedArrayBuffer layout: [header (8 floats), instance data, effects data]
//   Instance stride: 8 floats (32 bytes) per RenderInstance.
//   Effects stride: 5 floats (20 bytes) per vertex (x, y, z, u, v).

import init, {
  init_game,
  init_game_with_mode,
  tick_game,
  tap_tile,
  enable_bot,
  get_render_buffer_ptr,
  get_render_buffer_len,
  get_effects_buffer_ptr,
  get_effects_vertex_count,
  get_sound_events_ptr,
  get_sound_events_len,
  get_game_phase,
  get_game_mode,
  get_left_score,
  get_right_score,
  get_board_width,
  get_board_height,
  get_power_state,
  arm_power_left,
  arm_power_right,
  reset_game,
} from 'zapzap-sim';

// Instance stride in floats (8 floats = 32 bytes)
const INSTANCE_FLOATS = 8;
// Effects vertex stride in floats (5 floats = 20 bytes)
const EFFECTS_VERTEX_FLOATS = 5;

// SharedArrayBuffer layout:
// Header: 10 floats [lock, frame_counter, phase, left_score, right_score, instance_count, width, height, effects_vertex_count, reserved]
// Then: instance data (MAX_INSTANCES * 8 floats)
// Then: effects data (MAX_EFFECTS_VERTS * 5 floats)
const HEADER_FLOATS = 10;
const MAX_INSTANCES = 256;
const MAX_EFFECTS_VERTICES = 16384;
const INSTANCE_DATA_FLOATS = MAX_INSTANCES * INSTANCE_FLOATS;
const EFFECTS_DATA_FLOATS = MAX_EFFECTS_VERTICES * EFFECTS_VERTEX_FLOATS;
const BUFFER_FLOATS = HEADER_FLOATS + INSTANCE_DATA_FLOATS + EFFECTS_DATA_FLOATS;

let sharedBuffer: SharedArrayBuffer | null = null;
let sharedF32: Float32Array | null = null;
let sharedI32: Int32Array | null = null;
let running = false;
let wasmMemory: WebAssembly.Memory | null = null;

let gameMode = 0; // 0=Zen, 1=VsBot
let lastPhase = -1; // Track phase transitions for debug logging
let lastEffectsCount = 0; // Track effects to log changes
const PHASE_NAMES = ['WaitingForInput', 'RotatingTile', 'FallingTiles', 'FreezeDuringZap', 'FreezeDuringBomb', 'GameOver', 'FallingBonuses'];

async function initialize(mode: number = 0) {
  // Initialize WASM module
  const wasm = await init();
  wasmMemory = wasm.memory;
  gameMode = mode;
  lastPhase = -1;

  // Initialize game with a random seed and mode
  const seed = Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
  console.log(`[worker] init mode=${mode} seed=${seed}`);
  init_game_with_mode(seed, mode);

  // Allocate SharedArrayBuffer
  sharedBuffer = new SharedArrayBuffer(BUFFER_FLOATS * 4);
  sharedF32 = new Float32Array(sharedBuffer);
  sharedI32 = new Int32Array(sharedBuffer);

  // Send the SharedArrayBuffer to the main thread
  self.postMessage({ type: 'ready', sharedBuffer });
}

function gameLoop() {
  if (!running || !sharedF32 || !sharedI32 || !wasmMemory) return;

  try {
    const dt = 1.0 / 60.0; // Fixed timestep

    // Run simulation tick
    tick_game(dt);

    // Log phase transitions with details
    const phase = get_game_phase();
    if (phase !== lastPhase) {
      const name = PHASE_NAMES[phase] ?? `Unknown(${phase})`;
      const prevName = lastPhase >= 0 ? (PHASE_NAMES[lastPhase] ?? `Unknown(${lastPhase})`) : 'none';
      const evc = get_effects_vertex_count();
      const score = `L=${get_left_score()} R=${get_right_score()}`;
      console.log(`[worker] phase: ${prevName} -> ${name} | score: ${score} | effects_verts: ${evc} | instances: ${get_render_buffer_len()}`);
      lastPhase = phase;
    }

    // Log when effects appear or disappear
    const currentEffects = get_effects_vertex_count();
    if (currentEffects > 0 && lastEffectsCount === 0) {
      console.log(`[worker] effects appeared: ${currentEffects} vertices`);
    } else if (currentEffects === 0 && lastEffectsCount > 0) {
      console.log(`[worker] effects cleared (was ${lastEffectsCount} vertices)`);
    }
    lastEffectsCount = currentEffects;

    // Read render buffer from WASM memory
    const ptr = get_render_buffer_ptr() as unknown as number;
    const len = get_render_buffer_len();

    if (ptr && len > 0) {
      // Cap instances to buffer size
      const cappedLen = Math.min(len, MAX_INSTANCES);

      // Create a Float32Array view into WASM linear memory
      const wasmData = new Float32Array(wasmMemory.buffer, ptr, cappedLen * INSTANCE_FLOATS);

      // Read effects buffer
      const effectsPtr = get_effects_buffer_ptr() as unknown as number;
      const rawEffectsVertCount = get_effects_vertex_count();
      // Cap effects to buffer size to prevent overflow
      const effectsVertCount = Math.min(rawEffectsVertCount, MAX_EFFECTS_VERTICES);
      if (rawEffectsVertCount > MAX_EFFECTS_VERTICES) {
        console.warn(`[worker] effects vertex count ${rawEffectsVertCount} exceeds max ${MAX_EFFECTS_VERTICES}, capping`);
      }

      // Write header
      sharedF32[1] += 1; // frame counter
      sharedF32[2] = phase;
      sharedF32[3] = get_left_score();
      sharedF32[4] = get_right_score();
      sharedF32[5] = cappedLen;
      sharedF32[6] = get_board_width();
      sharedF32[7] = get_board_height();
      sharedF32[8] = effectsVertCount;
      sharedF32[9] = get_power_state();

      // Copy instance data after header
      sharedF32.set(wasmData, HEADER_FLOATS);

      // Copy effects data after instances
      if (effectsPtr && effectsVertCount > 0) {
        const effectsFloats = effectsVertCount * EFFECTS_VERTEX_FLOATS;
        const effectsData = new Float32Array(wasmMemory.buffer, effectsPtr, effectsFloats);
        sharedF32.set(effectsData, HEADER_FLOATS + INSTANCE_DATA_FLOATS);
      }

      // Forward sound events to main thread
      const soundPtr = get_sound_events_ptr() as unknown as number;
      const soundLen = get_sound_events_len();
      if (soundPtr && soundLen > 0) {
        const soundData = new Uint8Array(wasmMemory!.buffer, soundPtr, soundLen);
        const events = Array.from(soundData);
        self.postMessage({ type: 'sound', events });
      }

      // Notify main thread that new frame data is ready
      Atomics.store(sharedI32, 0, 1); // set lock to 1 = new frame
      Atomics.notify(sharedI32, 0);
    }
  } catch (err) {
    console.error('[worker] gameLoop error:', err);
    running = false; // Stop loop on error to prevent stuck state
    return;
  }

  // Schedule next tick
  if (running) {
    setTimeout(gameLoop, 16); // ~60fps
  }
}

self.onmessage = (e: MessageEvent) => {
  const { type } = e.data;

  switch (type) {
    case 'init':
      initialize(e.data.mode ?? 0).then(() => {
        running = true;
        gameLoop();
      });
      break;

    case 'tap': {
      const { x, y } = e.data;
      const phaseName = PHASE_NAMES[get_game_phase()] ?? `Unknown(${get_game_phase()})`;
      // Log tile instance data before tap (find instance at grid position)
      const ptr = get_render_buffer_ptr() as unknown as number;
      const len = get_render_buffer_len();
      let tileInfo = '';
      if (ptr && len > 0 && wasmMemory) {
        const buf = new Float32Array(wasmMemory.buffer, ptr, len * INSTANCE_FLOATS);
        // Search for instance matching this tile's expected position
        const expectedX = 225 + x * 50 + 25;
        const expectedY = 25 + y * 50 + 25;
        for (let i = 0; i < len; i++) {
          const ix = buf[i * 8 + 0];
          const iy = buf[i * 8 + 1];
          if (Math.abs(ix - expectedX) < 1 && Math.abs(iy - expectedY) < 1) {
            const rot = buf[i * 8 + 2].toFixed(3);
            const scale = buf[i * 8 + 3].toFixed(1);
            const spriteId = buf[i * 8 + 4];
            const alpha = buf[i * 8 + 5].toFixed(2);
            const flags = buf[i * 8 + 6];
            const atlasRow = buf[i * 8 + 7];
            tileInfo = ` | sprite=${spriteId} rot=${rot} alpha=${alpha} row=${atlasRow} flags=${flags}`;
            break;
          }
        }
      }
      const evc = get_effects_vertex_count();
      console.log(`[worker] tap (${x},${y}) phase=${phaseName} effects=${evc}${tileInfo}`);
      tap_tile(x, y);
      break;
    }

    case 'enable_bot': {
      enable_bot(e.data.enabled);
      break;
    }

    case 'reset': {
      const seed = e.data.seed ?? Math.floor(Math.random() * Number.MAX_SAFE_INTEGER);
      reset_game(seed);
      break;
    }

    case 'arm_power': {
      const { side, ptype } = e.data;
      if (side === 'left') {
        arm_power_left(ptype);
      } else {
        arm_power_right(ptype);
      }
      break;
    }

    case 'stop':
      running = false;
      break;

    case 'resume':
      if (!running && sharedF32 && sharedI32 && wasmMemory) {
        running = true;
        gameLoop();
      }
      break;
  }
};
