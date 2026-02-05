// Renderer factory — loads assets once, tries WebGPU, falls back to Canvas 2D.
// Re-exports the common Renderer interface for consumers.

export type { Renderer } from './types';

import { loadAssetBlobs } from './asset-loader';
import { initWebGPURenderer } from './webgpu';
import { initCanvas2DRenderer } from './canvas2d';
import type { Renderer } from './types';

/**
 * Probe WebGPU on a disposable canvas to avoid locking the real canvas.
 * If this fails, we skip straight to Canvas 2D without touching the real canvas.
 */
async function probeWebGPU(): Promise<boolean> {
  if (!navigator.gpu) return false;
  try {
    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) return false;
    const device = await adapter.requestDevice();
    const probe = document.createElement('canvas');
    probe.width = probe.height = 1;
    const ctx = probe.getContext('webgpu');
    if (!ctx) {
      device.destroy();
      return false;
    }
    // Test basic configure (preferred format, no HDR — most compatible)
    const format = navigator.gpu.getPreferredCanvasFormat();
    ctx.configure({ device, format, alphaMode: 'premultiplied' });
    ctx.unconfigure();
    device.destroy();
    return true;
  } catch {
    return false;
  }
}

/**
 * Initialize the best available renderer for the given canvas.
 * Fetches asset blobs once, then attempts WebGPU (HDR/EDR).
 * Falls back to Canvas 2D (SDR) if WebGPU is unavailable.
 */
export async function initRenderer(canvas: HTMLCanvasElement): Promise<Renderer> {
  const blobs = await loadAssetBlobs();

  // Probe WebGPU on a throwaway canvas before touching the real one.
  // This prevents canvas context locking if WebGPU fails entirely.
  const webgpuAvailable = await probeWebGPU();

  if (webgpuAvailable) {
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
