// Renderer factory — loads assets once, tries WebGPU, falls back to Canvas 2D.
// If WebGPU fails after acquiring a context (locking the canvas), it throws
// so the caller can remount the canvas DOM element before retrying with 2D.

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
  if (!navigator.gpu) {
    console.warn('[probeWebGPU] navigator.gpu is undefined');
    return false;
  }
  try {
    const adapter = await navigator.gpu.requestAdapter();
    if (!adapter) {
      console.warn('[probeWebGPU] requestAdapter returned null (GPU may be blocklisted)');
      return false;
    }
    console.log('[probeWebGPU] adapter:', 'info' in adapter ? (adapter as unknown as { info: unknown }).info : '(no info)');
    const device = await adapter.requestDevice();
    const probe = document.createElement('canvas');
    probe.width = probe.height = 1;
    const ctx = probe.getContext('webgpu');
    if (!ctx) {
      console.warn('[probeWebGPU] getContext("webgpu") returned null on probe canvas');
      device.destroy();
      return false;
    }
    const format = navigator.gpu.getPreferredCanvasFormat();
    ctx.configure({ device, format, alphaMode: 'premultiplied' });
    ctx.unconfigure();
    device.destroy();
    return true;
  } catch (e) {
    console.warn('[probeWebGPU] Failed:', e);
    return false;
  }
}

/**
 * Initialize the renderer.
 * If force2D is true, skips WebGPU entirely.
 * If WebGPU fails after touching the canvas, throws so the caller can
 * remount the canvas element before retrying with force2D=true.
 */
export async function initRenderer(
  canvas: HTMLCanvasElement,
  force2D = false,
): Promise<Renderer> {
  const blobs = await loadAssetBlobs();

  if (!force2D) {
    const webgpuAvailable = await probeWebGPU();
    if (webgpuAvailable) {
      try {
        return await initWebGPURenderer(canvas, blobs);
      } catch (e) {
        console.warn('[renderer] WebGPU init failed:', e);
        throw new Error('WebGPUInitFailed');
      }
    }
  }

  console.warn('[renderer] Using Canvas 2D fallback (no HDR/EDR)');
  return initCanvas2DRenderer(canvas, blobs);
}
