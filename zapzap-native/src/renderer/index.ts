// Renderer factory — loads assets once, tries WebGPU, falls back to Canvas 2D.
// Re-exports the common Renderer interface for consumers.

export type { Renderer } from './types';

import { loadAssetBlobs } from './asset-loader';
import { initWebGPURenderer } from './webgpu';
import { initCanvas2DRenderer } from './canvas2d';
import type { Renderer } from './types';

/**
 * Initialize the best available renderer for the given canvas.
 * Fetches asset blobs once, then attempts WebGPU (HDR/EDR).
 * Falls back to Canvas 2D (SDR) if WebGPU is unavailable.
 */
export async function initRenderer(canvas: HTMLCanvasElement): Promise<Renderer> {
  const blobs = await loadAssetBlobs();

  // Try WebGPU
  if (navigator.gpu) {
    try {
      return await initWebGPURenderer(canvas, blobs);
    } catch (e) {
      console.warn('[renderer] WebGPU init failed, falling back to Canvas 2D:', e);
    }
  }

  // Fallback to Canvas 2D
  console.warn('[renderer] Using Canvas 2D fallback (no HDR/EDR)');
  return initCanvas2DRenderer(canvas, blobs);
}
