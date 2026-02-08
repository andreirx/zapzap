#!/usr/bin/env python3
"""
Generate a single text blob of repo structure + file contents.
Focuses on CODE and DOCUMENTATION only — ignores assets (images, audio),
build artifacts (target/, pkg/, dist/), and generated files.
Respects .gitignore. Skipped entries are excluded from the tree entirely.
No external dependencies.
"""

import fnmatch
import os
from pathlib import Path

# Directories to always skip (never appear in tree or content)
ALWAYS_IGNORE_DIRS = {
    '.git', '.beads', '.idea', '.vscode', '.gradle', '.claude',
    'build', 'dist', 'node_modules', '__pycache__',
    'target',       # Rust/Cargo build output
    'pkg',          # wasm-pack output
    'public',       # static assets (images, audio) — not code
    '.vite',        # Vite dependency cache
    'cdk.out',      # CDK synthesized CloudFormation output
}

# File extensions to skip entirely (binary/generated, not code)
SKIP_EXTENSIONS = {
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.ico', '.svg',
    '.mp3', '.wav', '.ogg', '.flac', '.aac',
    '.wasm', '.o', '.so', '.dylib', '.a',
    '.zip', '.tar', '.gz', '.br',
    '.ttf', '.otf', '.woff', '.woff2',
    '.lock',
}

# Specific filenames to skip
SKIP_FILES = {
    'package-lock.json', 'yarn.lock', 'system-state.json',
    'repo-text-blob.py', 'repo_snapshot.txt',
    '.DS_Store', 'Cargo.lock', '.gitkeep',
}


def load_gitignore(root_path):
    """Parse .gitignore into a list of patterns."""
    gitignore_path = root_path / ".gitignore"
    if not gitignore_path.exists():
        return []
    with open(gitignore_path, 'r', encoding='utf-8') as f:
        return [
            line.strip() for line in f
            if line.strip() and not line.startswith('#')
        ]


def matches_gitignore(rel_path_str, patterns):
    """Check if a relative path matches any .gitignore pattern."""
    for pat in patterns:
        # Handle directory patterns (trailing /)
        check_pat = pat.rstrip('/')
        if fnmatch.fnmatch(rel_path_str, check_pat):
            return True
        # Also check basename
        if fnmatch.fnmatch(os.path.basename(rel_path_str), check_pat):
            return True
    return False


def should_skip(item, root_path, gitignore_patterns):
    """Return True if this file/dir should be excluded entirely."""
    name = item.name
    if item.is_dir():
        if name in ALWAYS_IGNORE_DIRS:
            return True
        # Also check gitignore for directories
        if gitignore_patterns:
            rel = str(item.relative_to(root_path))
            if matches_gitignore(rel, gitignore_patterns):
                return True
        return False
    # Skip by extension
    suffix = item.suffix.lower()
    if suffix in SKIP_EXTENSIONS:
        return True
    if name in SKIP_FILES:
        return True
    # Skip via gitignore
    if gitignore_patterns:
        rel = str(item.relative_to(root_path))
        if matches_gitignore(rel, gitignore_patterns):
            return True
    return False


def generate_tree(dir_path, root_path, gitignore_patterns, prefix=""):
    """Recursively generate tree structure, omitting ignored entries entirely."""
    entries = []
    try:
        items = sorted([
            x for x in dir_path.iterdir()
            if not should_skip(x, root_path, gitignore_patterns)
        ], key=lambda x: (not x.is_dir(), x.name))
    except PermissionError:
        return entries

    for i, item in enumerate(items):
        is_last = (i == len(items) - 1)
        connector = "└── " if is_last else "├── "
        entries.append(f"{prefix}{connector}{item.name}")

        if item.is_dir():
            extension = "    " if is_last else "│   "
            entries.extend(generate_tree(item, root_path, gitignore_patterns, prefix + extension))

    return entries


def read_file_safe(file_path):
    """Attempt to read file, return error message if binary/unreadable."""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return f.read()
    except (UnicodeDecodeError, PermissionError, OSError) as e:
        return f"[BINARY OR UNREADABLE: {type(e).__name__} {e}]"


def collect_files(root_path, gitignore_patterns):
    """Walk directory and collect code/doc files with content."""
    file_entries = []

    for dirpath, dirnames, filenames in os.walk(root_path):
        dp = Path(dirpath)
        # Prune ignored directories in-place
        dirnames[:] = sorted([
            d for d in dirnames
            if not should_skip(dp / d, root_path, gitignore_patterns)
        ])

        for filename in sorted(filenames):
            file_path = dp / filename
            if should_skip(file_path, root_path, gitignore_patterns):
                continue

            rel_path = file_path.relative_to(root_path)
            content = read_file_safe(file_path)
            file_entries.append(f"{rel_path};{content!r}")

    return file_entries


def main():
    root = Path.cwd()
    patterns = load_gitignore(root)

    output = []

    # Tree structure
    output.append("=== FOLDER TREE ===\n")
    output.append(f"{root.name}/")
    output.extend(generate_tree(root, root, patterns))
    output.append("\n")

    # File contents
    output.append("=== FILE CONTENTS ===\n")
    output.extend(collect_files(root, patterns))

    # Write to file
    output_file = root / "repo_snapshot.txt"
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("\n".join(output))

    print(f"Generated: {output_file}")


if __name__ == "__main__":
    main()
