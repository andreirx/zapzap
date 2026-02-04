// Async texture loader for game assets.
// Loads PNGs from public/assets/ and creates GPUTextures.

export interface TextureAsset {
  texture: GPUTexture;
  view: GPUTextureView;
  width: number;
  height: number;
}

/** Load a single image as a GPUTexture. */
export async function loadTexture(
  device: GPUDevice,
  url: string,
): Promise<TextureAsset> {
  const response = await fetch(url);
  const blob = await response.blob();
  const bitmap = await createImageBitmap(blob, {
    colorSpaceConversion: 'none',
    premultiplyAlpha: 'premultiply',
  });

  const texture = device.createTexture({
    size: { width: bitmap.width, height: bitmap.height },
    format: 'rgba8unorm',
    usage:
      GPUTextureUsage.TEXTURE_BINDING |
      GPUTextureUsage.COPY_DST |
      GPUTextureUsage.RENDER_ATTACHMENT,
  });

  device.queue.copyExternalImageToTexture(
    { source: bitmap },
    { texture },
    { width: bitmap.width, height: bitmap.height },
  );

  bitmap.close();

  return {
    texture,
    view: texture.createView(),
    width: bitmap.width,
    height: bitmap.height,
  };
}

/** All game textures keyed by name. */
export interface GameTextures {
  baseTiles: TextureAsset;
  baseTilesHalloween: TextureAsset;
  arrows: TextureAsset;
  arrowsHalloween: TextureAsset;
  stars: TextureAsset;
  superhero: TextureAsset;
  colorMap: TextureAsset;
  companyLogo: TextureAsset;
}

/** Load all game textures. Returns a map of named texture assets. */
export async function loadAllTextures(
  device: GPUDevice,
): Promise<GameTextures> {
  const [
    baseTiles,
    baseTilesHalloween,
    arrows,
    arrowsHalloween,
    stars,
    superhero,
    colorMap,
    companyLogo,
  ] = await Promise.all([
    loadTexture(device, '/assets/base_tiles.png'),
    loadTexture(device, '/assets/base_tiles_haloween.png'),
    loadTexture(device, '/assets/arrows.png'),
    loadTexture(device, '/assets/arrows_haloween.png'),
    loadTexture(device, '/assets/stars.png'),
    loadTexture(device, '/assets/superhero.png'),
    loadTexture(device, '/assets/ColorMap.png'),
    loadTexture(device, '/assets/companylogo.png'),
  ]);

  return {
    baseTiles,
    baseTilesHalloween,
    arrows,
    arrowsHalloween,
    stars,
    superhero,
    colorMap,
    companyLogo,
  };
}
