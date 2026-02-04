// Renderer factory — tries WebGPU first, falls back to Canvas 2D.
// Re-exports the common Renderer interface for consumers.

export type { Renderer } from './types';

import { initWebGPURenderer } from './webgpu';
import { initCanvas2DRenderer } from './canvas2d';
import type { Renderer } from './types';

/**
 * Initialize the best available renderer for the given canvas.
 * Attempts WebGPU (HDR/EDR) first; falls back to Canvas 2D (SDR).
 */
export async function initRenderer(canvas: HTMLCanvasElement): Promise<Renderer> {
  // Try WebGPU
  if (navigator.gpu) {
    try {
      const renderer = await initWebGPURenderer(canvas);
      return renderer;
    } catch (e) {
      console.warn('[renderer] WebGPU init failed, falling back to Canvas 2D:', e);
    }
  }

  // Fallback to Canvas 2D
  console.warn('[renderer] Using Canvas 2D fallback (no HDR/EDR)');
  return initCanvas2DRenderer(canvas);
}
