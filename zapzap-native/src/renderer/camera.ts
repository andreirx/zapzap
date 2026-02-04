// Shared camera/projection math — used by both WebGPU and Canvas 2D renderers.
// Computes aspect-preserving orthographic projection for the 1050×550 game area.

import { GAME_WIDTH, GAME_HEIGHT } from './constants';

export interface Projection {
  projWidth: number;
  projHeight: number;
  scaleX: number;
  scaleY: number;
}

/** Compute aspect-preserving projection dimensions and scale factors. */
export function computeProjection(canvasW: number, canvasH: number): Projection {
  const aspect = canvasW / canvasH;
  const gameAspect = GAME_WIDTH / GAME_HEIGHT;
  let projWidth = GAME_WIDTH;
  let projHeight = GAME_HEIGHT;
  if (aspect > gameAspect) {
    projWidth = GAME_HEIGHT * aspect;
  } else {
    projHeight = GAME_WIDTH / aspect;
  }
  return {
    projWidth,
    projHeight,
    scaleX: canvasW / projWidth,
    scaleY: canvasH / projHeight,
  };
}

/** Build column-major orthographic projection matrix for WebGPU. */
export function buildProjectionMatrix(canvasW: number, canvasH: number): Float32Array {
  const { projWidth, projHeight } = computeProjection(canvasW, canvasH);
  const l = 0, r = projWidth, b = projHeight, t = 0;
  return new Float32Array([
    2 / (r - l), 0, 0, 0,
    0, 2 / (t - b), 0, 0,
    0, 0, 1, 0,
    -(r + l) / (r - l), -(t + b) / (t - b), 0, 1,
  ]);
}
