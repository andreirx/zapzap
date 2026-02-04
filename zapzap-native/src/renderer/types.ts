// Common Renderer interface — implemented by both WebGPU and Canvas 2D backends.
// The game engine (Rust/WASM) outputs coordinates to memory; this interface
// abstracts how those coordinates are drawn on screen.

export interface Renderer {
  /** The active backend: 'webgpu' for HDR/EDR, 'canvas2d' for fallback. */
  backend: 'webgpu' | 'canvas2d';

  /**
   * Draw one frame of the game.
   * @param instanceData  Flat float array of sprites (8 floats each: x, y, rot, scale, sprite_id, alpha, flags, atlas_row)
   * @param instanceCount Total sprite instances
   * @param tileInstanceCount How many are tiles/pins (drawn with base_tiles atlas); rest are bonuses (arrows atlas)
   * @param effectsData   Optional flat float array of effect vertices (5 floats each: x, y, z, u, v)
   * @param effectsVertexCount Total effect vertices
   */
  draw: (
    instanceData: Float32Array,
    instanceCount: number,
    tileInstanceCount: number,
    effectsData?: Float32Array,
    effectsVertexCount?: number,
  ) => void;

  /** Handle canvas resize. */
  resize: (width: number, height: number) => void;
}
