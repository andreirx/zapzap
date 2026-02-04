#!/usr/bin/env python3
"""
extract_assets.py — Flatten .xcassets and AudioResources into Vite-servable directories.

Walks the Xcode asset catalog and copies image/audio files into:
  - public/assets/  (PNGs, JPGs from .textureset/.imageset)
  - public/audio/   (MP3s, WAVs from AudioResources)
"""

import json
import shutil
import sys
from pathlib import Path

# Paths relative to this script's location (zapzap-native/scripts/)
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent  # zapzap-native/
REPO_ROOT = PROJECT_ROOT.parent   # ZapZap/

XCASSETS_DIR = REPO_ROOT / "ZapZap Shared" / "Assets.xcassets"
AUDIO_DIR = REPO_ROOT / "ZapZap Shared" / "AudioResources"

OUT_ASSETS = PROJECT_ROOT / "public" / "assets"
OUT_AUDIO = PROJECT_ROOT / "public" / "audio"

IMAGE_EXTS = {".png", ".jpg", ".jpeg"}
AUDIO_EXTS = {".mp3", ".wav"}

# Assets we skip (not needed for the game renderer)
SKIP_DIRS = {"AccentColor.colorset", "AppIcon.appiconset"}


def extract_textures():
    """Walk .xcassets, find image files inside .textureset/.imageset dirs, copy them out."""
    OUT_ASSETS.mkdir(parents=True, exist_ok=True)
    count = 0

    if not XCASSETS_DIR.exists():
        print(f"WARNING: {XCASSETS_DIR} not found, skipping texture extraction")
        return count

    for asset_dir in sorted(XCASSETS_DIR.iterdir()):
        if not asset_dir.is_dir():
            continue
        if asset_dir.name in SKIP_DIRS:
            continue

        # Derive a clean asset name from the directory name
        # e.g. "base_tiles.textureset" -> "base_tiles"
        asset_name = asset_dir.stem  # removes .textureset / .imageset

        # Walk into the asset dir to find image files
        for img_file in sorted(asset_dir.rglob("*")):
            if img_file.suffix.lower() in IMAGE_EXTS:
                # Use the asset_name as the output filename, preserving original extension
                # Special case: if the actual filename differs significantly (e.g. arrows-haloween.png
                # inside arrows_haloween.textureset), use the directory-derived name for consistency
                out_name = f"{asset_name}{img_file.suffix.lower()}"
                out_path = OUT_ASSETS / out_name

                shutil.copy2(img_file, out_path)
                print(f"  [IMG] {img_file.name} -> {out_path.relative_to(PROJECT_ROOT)}")
                count += 1

    return count


def extract_audio():
    """Copy MP3/WAV files from AudioResources to public/audio/."""
    OUT_AUDIO.mkdir(parents=True, exist_ok=True)
    count = 0

    if not AUDIO_DIR.exists():
        print(f"WARNING: {AUDIO_DIR} not found, skipping audio extraction")
        return count

    for audio_file in sorted(AUDIO_DIR.iterdir()):
        if audio_file.suffix.lower() in AUDIO_EXTS:
            out_path = OUT_AUDIO / audio_file.name
            shutil.copy2(audio_file, out_path)
            print(f"  [SFX] {audio_file.name} -> {out_path.relative_to(PROJECT_ROOT)}")
            count += 1

    return count


def main():
    print(f"Asset Extraction")
    print(f"  xcassets:  {XCASSETS_DIR}")
    print(f"  audio:     {AUDIO_DIR}")
    print(f"  out imgs:  {OUT_ASSETS}")
    print(f"  out audio: {OUT_AUDIO}")
    print()

    img_count = extract_textures()
    print(f"\nExtracted {img_count} image(s)\n")

    audio_count = extract_audio()
    print(f"\nExtracted {audio_count} audio file(s)\n")

    total = img_count + audio_count
    if total == 0:
        print("WARNING: No assets extracted!")
        sys.exit(1)
    else:
        print(f"Done. {total} files total.")


if __name__ == "__main__":
    main()
