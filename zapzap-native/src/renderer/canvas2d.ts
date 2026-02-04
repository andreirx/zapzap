// Canvas 2D fallback renderer — used when WebGPU is unavailable (e.g. Firefox).
// Lower visual quality (no HDR/EDR, simplified effects) but fully functional.
// Same Renderer interface as WebGPU backend; driven by SharedArrayBuffer data.

import { createCanvasImages, type AssetBlobs } from './asset-loader';
import { computeProjection } from './camera';
import { SEGMENT_COLORS_RGB8 } from './constants';
import type { Renderer } from './types';

const TILE_SIZE = 50;
const INSTANCE_FLOATS = 8;
const EFFECTS_VERTEX_FLOATS = 5;

export async function initCanvas2DRenderer(
  canvas: HTMLCanvasElement,
  blobs: AssetBlobs,
): Promise<Renderer> {
  const ctx = canvas.getContext('2d');
  if (!ctx) {
    throw new Error('Failed to get Canvas 2D context');
  }

  // Create HTMLImageElements from pre-fetched blobs
  const images = await createCanvasImages(blobs);

  // Atlas dimensions
  const BASE_COLS = 16;
  const BASE_ROWS = 8;
  const ARROWS_COLS = 8;
  const ARROWS_ROWS = 8;

  const baseCellW = images.baseTiles.width / BASE_COLS;
  const baseCellH = images.baseTiles.height / BASE_ROWS;
  const arrowsCellW = images.arrows.width / ARROWS_COLS;
  const arrowsCellH = images.arrows.height / ARROWS_ROWS;

  // ---- Instance drawing (tiles + bonuses) ----

  function drawInstance(
    c: CanvasRenderingContext2D,
    data: Float32Array,
    off: number,
    atlas: HTMLImageElement,
    cols: number,
    cellW: number,
    cellH: number,
  ) {
    const x = data[off];
    const y = data[off + 1];
    const rotation = data[off + 2];
    const scale = data[off + 3];
    const spriteId = data[off + 4];
    const alpha = data[off + 5];
    const flags = data[off + 6];
    const atlasRow = data[off + 7];

    if (alpha <= 0) return;

    const cellCount = Math.max(flags, 1);
    const col = spriteId % cols;

    // Source rectangle in atlas
    const srcX = col * cellW;
    const srcY = atlasRow * cellH;
    const srcW = cellCount * cellW;
    const srcH = cellCount * cellH;

    // Destination size in game units
    const size = TILE_SIZE * scale;
    const half = size * 0.5;

    c.globalAlpha = alpha;

    if (rotation === 0) {
      // Fast path: skip save/translate/rotate/restore for non-rotated tiles.
      // Most tiles (~119/120) are static; this avoids expensive state stack ops.
      c.drawImage(atlas, srcX, srcY, srcW, srcH, x - half, y - half, size, size);
    } else {
      // Slow path: rotated tile (player interaction, animations)
      c.save();
      c.translate(x, y);
      c.rotate(rotation);
      c.drawImage(atlas, srcX, srcY, srcW, srcH, -half, -half, size, size);
      c.restore();
    }
  }

  // ---- Effects drawing (arcs + particles) ----

  function drawEffectsTriangle(
    c: CanvasRenderingContext2D,
    data: Float32Array,
    v0Index: number,
  ) {
    const off0 = v0Index * EFFECTS_VERTEX_FLOATS;
    const off1 = (v0Index + 1) * EFFECTS_VERTEX_FLOATS;
    const off2 = (v0Index + 2) * EFFECTS_VERTEX_FLOATS;

    const x0 = data[off0], y0 = data[off0 + 1];
    const x1 = data[off1], y1 = data[off1 + 1];
    const x2 = data[off2], y2 = data[off2 + 1];

    // Color from z-channel of first vertex (SegmentColor enum index)
    const colorIdx = Math.round(data[off0 + 2]);
    const [r, g, b] = SEGMENT_COLORS_RGB8[Math.min(Math.max(colorIdx, 0), SEGMENT_COLORS_RGB8.length - 1)];

    // Approximate lightsaber brightness from UV:
    // u = cross-strip (0=edge, 0.5=center, 1=edge), v = along-strip (0=tip, 1=body)
    const u0 = data[off0 + 3], u1 = data[off1 + 3], u2 = data[off2 + 3];
    const v0v = data[off0 + 4], v1v = data[off1 + 4], v2v = data[off2 + 4];
    const avgU = (u0 + u1 + u2) / 3;
    const avgV = (v0v + v1v + v2v) / 3;

    // Halo falloff from center
    const d = Math.abs(avgU * 2 - 1);
    const halo = Math.exp(-d * d * 3);
    const a = halo * avgV;
    if (a < 0.02) return;

    c.beginPath();
    c.moveTo(x0, y0);
    c.lineTo(x1, y1);
    c.lineTo(x2, y2);
    c.closePath();
    c.fillStyle = `rgba(${r}, ${g}, ${b}, ${Math.min(a, 1).toFixed(3)})`;
    c.fill();
  }

  // ---- Main draw function ----

  function draw(
    instanceData: Float32Array,
    instanceCount: number,
    tileInstanceCount: number,
    effectsData?: Float32Array,
    effectsVertexCount?: number,
  ) {
    const w = canvas.width;
    const h = canvas.height;
    const { scaleX, scaleY } = computeProjection(w, h);

    // Clear
    ctx!.globalCompositeOperation = 'source-over';
    ctx!.globalAlpha = 1;
    ctx!.fillStyle = '#05050d';
    ctx!.fillRect(0, 0, w, h);

    // Transform: game units -> canvas pixels
    ctx!.save();
    ctx!.scale(scaleX, scaleY);

    // Pass 1a: Tile + pin instances (base_tiles atlas, 16x8)
    for (let i = 0; i < tileInstanceCount; i++) {
      drawInstance(ctx!, instanceData, i * INSTANCE_FLOATS, images.baseTiles, BASE_COLS, baseCellW, baseCellH);
    }

    // Pass 1b: Bonus instances (arrows atlas, 8x8)
    for (let i = tileInstanceCount; i < instanceCount; i++) {
      drawInstance(ctx!, instanceData, i * INSTANCE_FLOATS, images.arrows, ARROWS_COLS, arrowsCellW, arrowsCellH);
    }

    // Pass 2: Effects (additive blend — arcs + particles)
    const hasEffects = effectsData && effectsVertexCount && effectsVertexCount > 0;
    if (hasEffects) {
      ctx!.globalCompositeOperation = 'lighter';
      ctx!.globalAlpha = 1;
      const triCount = Math.floor(effectsVertexCount / 3);
      for (let t = 0; t < triCount; t++) {
        drawEffectsTriangle(ctx!, effectsData, t * 3);
      }
      ctx!.globalCompositeOperation = 'source-over';
    }

    ctx!.restore();
  }

  function resize(width: number, height: number) {
    canvas.width = width;
    canvas.height = height;
  }

  return { backend: 'canvas2d', draw, resize };
}
