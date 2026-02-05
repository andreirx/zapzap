// Unified asset loader — fetches image blobs once, creates format-specific
// resources (GPUTexture or HTMLImageElement) on demand.
// Prevents double-downloading when WebGPU fails and we fall back to Canvas 2D.

// Asset manifest — only the atlases actively used in rendering.
const ASSET_URLS = {
  baseTiles: '/assets/base_tiles.png',
  arrows: '/assets/arrows.png',
} as const;

type AssetKey = keyof typeof ASSET_URLS;

export interface AssetBlobs {
  baseTiles: Blob;
  arrows: Blob;
}

/** Fetch all game asset PNGs as raw Blobs (renderer-agnostic). */
export async function loadAssetBlobs(): Promise<AssetBlobs> {
  const keys = Object.keys(ASSET_URLS) as AssetKey[];

  const fetchWithLog = async (key: AssetKey) => {
    const url = ASSET_URLS[key];
    console.log(`[AssetLoader] Fetching: ${key} -> ${url}`);

    try {
      const resp = await fetch(url);
      console.log(`[AssetLoader] ${key} status: ${resp.status} (${resp.statusText})`);

      if (!resp.ok) {
        throw new Error(`HTTP ${resp.status} fetching ${url}`);
      }

      const type = resp.headers.get('Content-Type');
      console.log(`[AssetLoader] ${key} content-type: ${type}`);
      if (type && !type.startsWith('image/')) {
        throw new Error(`Expected image, got ${type} for ${url}`);
      }

      const blob = await resp.blob();
      console.log(`[AssetLoader] ${key} size: ${blob.size} bytes`);
      return [key, blob] as const;
    } catch (e) {
      console.error(`[AssetLoader] FAILED to load ${key}:`, e);
      throw e;
    }
  };

  const entries = await Promise.all(keys.map(fetchWithLog));
  return Object.fromEntries(entries) as unknown as AssetBlobs;
}

// ---- WebGPU: Blob → ImageBitmap → GPUTexture ----

export interface GPUTextureAsset {
  texture: GPUTexture;
  view: GPUTextureView;
  width: number;
  height: number;
}

async function createGPUTextureFromBlob(
  device: GPUDevice,
  blob: Blob,
): Promise<GPUTextureAsset> {
  const bitmap = await createImageBitmap(blob, {
    colorSpaceConversion: 'none',
    premultiplyAlpha: 'premultiply',
  });

  const width = bitmap.width;
  const height = bitmap.height;

  const texture = device.createTexture({
    size: { width, height },
    format: 'rgba8unorm',
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });

  device.queue.copyExternalImageToTexture(
    { source: bitmap },
    { texture },
    { width, height },
  );

  bitmap.close();

  return { texture, view: texture.createView(), width, height };
}

export interface GameGPUTextures {
  baseTiles: GPUTextureAsset;
  arrows: GPUTextureAsset;
}

/** Create GPU textures from pre-loaded blobs. */
export async function createGPUTextures(
  device: GPUDevice,
  blobs: AssetBlobs,
): Promise<GameGPUTextures> {
  const [baseTiles, arrows] = await Promise.all([
    createGPUTextureFromBlob(device, blobs.baseTiles),
    createGPUTextureFromBlob(device, blobs.arrows),
  ]);
  return { baseTiles, arrows };
}

// ---- Canvas 2D: Blob → Object URL → HTMLImageElement ----

export interface CanvasImages {
  baseTiles: HTMLImageElement;
  arrows: HTMLImageElement;
}

function createImageFromBlob(blob: Blob): Promise<HTMLImageElement> {
  const url = URL.createObjectURL(blob);
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = reject;
    img.src = url;
  });
}

/** Create HTMLImageElements from pre-loaded blobs for Canvas 2D. */
export async function createCanvasImages(blobs: AssetBlobs): Promise<CanvasImages> {
  const [baseTiles, arrows] = await Promise.all([
    createImageFromBlob(blobs.baseTiles),
    createImageFromBlob(blobs.arrows),
  ]);
  return { baseTiles, arrows };
}
