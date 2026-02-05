// WebGPU renderer — reads simulation state from SharedArrayBuffer and draws.
// Configures rgba16float + display-p3 + extended tone mapping for HDR/EDR.
// Two-pass rendering: Pass 1 (tiles, alpha blend) + Pass 2 (arcs/particles, additive).

import shaderSource from './shaders.wgsl?raw';
import { createGPUTextures, type AssetBlobs } from './asset-loader';
import { buildProjectionMatrix } from './camera';
import { packColorsForGPU } from './constants';
import type { Renderer } from './types';

// Bytes per RenderInstance: 8 × f32 = 32 bytes
const INSTANCE_STRIDE = 32;
// Max instances we can render
const MAX_INSTANCES = 256;
// Effects vertex: 5 floats = 20 bytes (x, y, z, u, v)
const EFFECTS_VERTEX_FLOATS = 5;
const EFFECTS_VERTEX_BYTES = EFFECTS_VERTEX_FLOATS * 4;
const MAX_EFFECTS_VERTICES = 16384;

export async function initWebGPURenderer(
  canvas: HTMLCanvasElement,
  blobs: AssetBlobs,
): Promise<Renderer> {
  // ---- GPU Init ----
  if (!navigator.gpu) {
    throw new Error('WebGPU not supported');
  }

  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error('No WebGPU adapter found');
  }

  const device = await adapter.requestDevice();
  const context = canvas.getContext('webgpu');
  if (!context) {
    throw new Error('Failed to get WebGPU context');
  }

  // Progressive configure — try full HDR, then basic rgba16float, then preferred format.
  // This prevents a TypeError from locking the canvas and blocking Canvas 2D fallback.
  let format: GPUTextureFormat = 'rgba16float';
  let useHDR = false;

  try {
    context.configure({
      device,
      format: 'rgba16float',
      colorSpace: 'display-p3',
      toneMapping: { mode: 'extended' },
      alphaMode: 'premultiplied',
    });
    useHDR = true;
  } catch {
    try {
      context.configure({
        device,
        format: 'rgba16float',
        alphaMode: 'premultiplied',
      });
    } catch {
      format = navigator.gpu.getPreferredCanvasFormat();
      context.configure({
        device,
        format,
        alphaMode: 'premultiplied',
      });
    }
  }

  if (!useHDR) {
    console.warn('[renderer] HDR/EDR not available, using sRGB WebGPU');
  }

  // ---- Load textures from pre-fetched blobs ----
  const textures = await createGPUTextures(device, blobs);

  // ---- Shader Module ----
  const shaderModule = device.createShaderModule({
    code: shaderSource,
  });

  // ---- Camera Uniform ----
  const cameraBuffer = device.createBuffer({
    size: 64, // mat4x4<f32> = 16 × 4 bytes
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });

  const cameraBindGroupLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: 'uniform' },
      },
    ],
  });

  const cameraBindGroup = device.createBindGroup({
    layout: cameraBindGroupLayout,
    entries: [{ binding: 0, resource: { buffer: cameraBuffer } }],
  });

  // ---- Segment Colors UBO (for effects pipeline) ----
  // 13 × vec4<f32> = 208 bytes — uploaded once, colors are static.
  const colorsData = packColorsForGPU();
  const colorsBuffer = device.createBuffer({
    size: colorsData.byteLength,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  device.queue.writeBuffer(colorsBuffer, 0, colorsData);

  const colorsBindGroupLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.FRAGMENT,
        buffer: { type: 'uniform' },
      },
    ],
  });

  const colorsBindGroup = device.createBindGroup({
    layout: colorsBindGroupLayout,
    entries: [{ binding: 0, resource: { buffer: colorsBuffer } }],
  });

  // ---- Texture Bind Group (base_tiles) ----
  const textureBindGroupLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.FRAGMENT,
        texture: { sampleType: 'float' },
      },
      {
        binding: 1,
        visibility: GPUShaderStage.FRAGMENT,
        sampler: { type: 'filtering' },
      },
    ],
  });

  const sampler = device.createSampler({
    magFilter: 'linear',
    minFilter: 'linear',
    mipmapFilter: 'linear',
  });

  const textureBindGroup = device.createBindGroup({
    layout: textureBindGroupLayout,
    entries: [
      { binding: 0, resource: textures.baseTiles.view },
      { binding: 1, resource: sampler },
    ],
  });

  // ---- Arrows texture bind group (for effects/arcs + bonus sprites) ----
  const arrowsBindGroup = device.createBindGroup({
    layout: textureBindGroupLayout,
    entries: [
      { binding: 0, resource: textures.arrows.view },
      { binding: 1, resource: sampler },
    ],
  });

  // ---- Instance Storage Buffer (tiles) ----
  const instanceBuffer = device.createBuffer({
    size: INSTANCE_STRIDE * MAX_INSTANCES,
    usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
  });

  const instanceBindGroupLayout = device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX,
        buffer: { type: 'read-only-storage' },
      },
    ],
  });

  const instanceBindGroup = device.createBindGroup({
    layout: instanceBindGroupLayout,
    entries: [{ binding: 0, resource: { buffer: instanceBuffer } }],
  });

  // ---- Effects Vertex Buffer (arcs + particles) ----
  const effectsBuffer = device.createBuffer({
    size: EFFECTS_VERTEX_BYTES * MAX_EFFECTS_VERTICES,
    usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
  });

  // ---- Pipeline Layout (tiles) ----
  const tilePipelineLayout = device.createPipelineLayout({
    bindGroupLayouts: [
      cameraBindGroupLayout,    // group 0
      textureBindGroupLayout,   // group 1
      instanceBindGroupLayout,  // group 2
    ],
  });

  // ---- Pipeline Layout (effects — vertex buffer + colors UBO at group 3) ----
  // Group 2 is null (unused by effects; occupied by instances in tile pipeline).
  const effectsPipelineLayout = device.createPipelineLayout({
    bindGroupLayouts: [
      cameraBindGroupLayout,    // group 0
      textureBindGroupLayout,   // group 1
      null,                     // group 2 (not used by effects)
      colorsBindGroupLayout,    // group 3
    ],
  });

  // Alpha blend state shared by tile and bonus pipelines
  const alphaBlendTargets: GPUColorTargetState[] = [
    {
      format,
      blend: {
        color: {
          srcFactor: 'src-alpha',
          dstFactor: 'one-minus-src-alpha',
          operation: 'add',
        },
        alpha: {
          srcFactor: 'one',
          dstFactor: 'one-minus-src-alpha',
          operation: 'add',
        },
      },
    },
  ];

  // ---- Alpha Blend Pipeline (tiles — 16×8 base_tiles atlas) ----
  const alphaPipeline = device.createRenderPipeline({
    layout: tilePipelineLayout,
    vertex: {
      module: shaderModule,
      entryPoint: 'vs_main',
      constants: { ATLAS_COLS: 16, ATLAS_ROWS: 8 },
    },
    fragment: {
      module: shaderModule,
      entryPoint: 'fs_main',
      targets: alphaBlendTargets,
    },
    primitive: {
      topology: 'triangle-list',
    },
  });

  // ---- Alpha Blend Pipeline (bonuses — 8×8 arrows atlas) ----
  const arrowsAlphaPipeline = device.createRenderPipeline({
    layout: tilePipelineLayout,
    vertex: {
      module: shaderModule,
      entryPoint: 'vs_main',
      constants: { ATLAS_COLS: 8, ATLAS_ROWS: 8 },
    },
    fragment: {
      module: shaderModule,
      entryPoint: 'fs_main',
      targets: alphaBlendTargets,
    },
    primitive: {
      topology: 'triangle-list',
    },
  });

  // ---- Additive Pipeline (effects: arcs + particles) ----
  const additivePipeline = device.createRenderPipeline({
    layout: effectsPipelineLayout,
    vertex: {
      module: shaderModule,
      entryPoint: 'vs_effects',
      buffers: [
        {
          // Effects vertex buffer: 5 floats (x, y, z, u, v)
          arrayStride: EFFECTS_VERTEX_BYTES,
          attributes: [
            { shaderLocation: 0, offset: 0, format: 'float32x3' },   // position (x, y, z)
            { shaderLocation: 1, offset: 12, format: 'float32x2' },  // tex_coord (u, v)
          ],
        },
      ],
    },
    fragment: {
      module: shaderModule,
      entryPoint: 'fs_additive',
      targets: [
        {
          format,
          blend: {
            color: {
              srcFactor: 'src-alpha',
              dstFactor: 'one',
              operation: 'add',
            },
            alpha: {
              srcFactor: 'one',
              dstFactor: 'one',
              operation: 'add',
            },
          },
        },
      ],
    },
    primitive: {
      topology: 'triangle-list',
    },
  });

  // ---- Camera Projection ----
  function updateCamera(width: number, height: number) {
    device.queue.writeBuffer(cameraBuffer, 0, buildProjectionMatrix(width, height));
  }

  updateCamera(canvas.width, canvas.height);

  // ---- Draw Function ----
  function draw(instanceData: Float32Array, instanceCount: number, tileInstanceCount: number, effectsData?: Float32Array, effectsVertexCount?: number) {
    // Upload instance data
    const byteLen = instanceCount * INSTANCE_STRIDE;
    device.queue.writeBuffer(instanceBuffer, 0, instanceData.buffer, instanceData.byteOffset, byteLen);

    // Upload effects data if present
    const hasEffects = effectsData && effectsVertexCount && effectsVertexCount > 0;
    if (hasEffects) {
      const effectsByteLen = effectsVertexCount * EFFECTS_VERTEX_BYTES;
      device.queue.writeBuffer(effectsBuffer, 0, effectsData.buffer, effectsData.byteOffset, effectsByteLen);
    }

    const encoder = device.createCommandEncoder();
    const textureView = context!.getCurrentTexture().createView();

    const pass = encoder.beginRenderPass({
      colorAttachments: [
        {
          view: textureView,
          clearValue: { r: 0.02, g: 0.02, b: 0.05, a: 1.0 },
          loadOp: 'clear',
          storeOp: 'store',
        },
      ],
    });

    // Pass 1a: Tiles + pins (alpha blend, base_tiles.png, 16×8 atlas)
    if (tileInstanceCount > 0) {
      pass.setPipeline(alphaPipeline);
      pass.setBindGroup(0, cameraBindGroup);
      pass.setBindGroup(1, textureBindGroup);
      pass.setBindGroup(2, instanceBindGroup);
      pass.draw(6, tileInstanceCount);
    }

    // Pass 1b: Bonus objects (alpha blend, arrows.png, 8×8 atlas)
    const bonusCount = instanceCount - tileInstanceCount;
    if (bonusCount > 0) {
      pass.setPipeline(arrowsAlphaPipeline);
      pass.setBindGroup(0, cameraBindGroup);
      pass.setBindGroup(1, arrowsBindGroup);
      pass.setBindGroup(2, instanceBindGroup);
      pass.draw(6, bonusCount, 0, tileInstanceCount);
    }

    // Pass 2: Effects (additive blend) — arcs + particles
    if (hasEffects) {
      pass.setPipeline(additivePipeline);
      pass.setBindGroup(0, cameraBindGroup);
      pass.setBindGroup(1, arrowsBindGroup);
      pass.setBindGroup(3, colorsBindGroup);
      pass.setVertexBuffer(0, effectsBuffer);
      pass.draw(effectsVertexCount!);
    }

    pass.end();
    device.queue.submit([encoder.finish()]);
  }

  function resize(width: number, height: number) {
    canvas.width = width;
    canvas.height = height;
    if (useHDR) {
      context!.configure({
        device,
        format,
        colorSpace: 'display-p3',
        toneMapping: { mode: 'extended' },
        alphaMode: 'premultiplied',
      });
    } else {
      context!.configure({
        device,
        format,
        alphaMode: 'premultiplied',
      });
    }
    updateCamera(width, height);
  }

  return { backend: 'webgpu', draw, resize };
}
