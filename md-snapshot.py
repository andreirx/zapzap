#!/usr/bin/env python3
"""
Gather all .md files from the current directory and subdirectories
into a single md-snapshot.txt file.
"""

import os
from pathlib import Path

ALWAYS_IGNORE = {'.git', '.beads', '.idea', '.vscode', '.gradle', 'build', 'dist', 'node_modules', '__pycache__'}

def read_file_safe(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read()
    except (UnicodeDecodeError, PermissionError, OSError) as e:
        return f"[UNREADABLE: {type(e).__name__} {e}]"

def collect_md_files(root_path):
    entries = []

    for dirpath, dirnames, filenames in os.walk(root_path):
        dirnames[:] = sorted(d for d in dirnames if d not in ALWAYS_IGNORE)

        for filename in sorted(filenames):
            if not filename.lower().endswith('.md'):
                continue

            file_path = Path(dirpath) / filename
            rel_path = file_path.relative_to(root_path)
            content = read_file_safe(file_path)

            entries.append((str(rel_path), content))

    return entries

def main():
    root = Path.cwd()
    md_files = collect_md_files(root)

    output = []
    output.append(f"=== MD SNAPSHOT ({len(md_files)} files) ===\n")

    for rel_path, content in md_files:
        output.append(f"--- {rel_path} ---")
        output.append(content)
        output.append("")

    output_file = root / "md-snapshot.txt"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("\n".join(output))

    print(f"Generated: {output_file} ({len(md_files)} markdown files)")

if __name__ == "__main__":
    main()
