# Zig Reference Snapshots

This directory contains offline, versioned snapshots of the Zig language reference, formatted for quick navigation and agent-friendly loading.

## Versions

- Zig 0.15.1
- One-page reference: `0.15.1/zig-0.15.1.md`
  - Best for full-text search; ~530 KB
  - Per-section split: `0.15.1/README.md`
  - 51 files, one per top-level section
  - Themed chapters: `0.15.1/CHAPTERS.md`
    - ~12 files grouped by topic; large chapters split into parts to keep file sizes reasonable

## Maintenance

- Rebuild per-section split: `python3 scripts/split_zig_doc.py`
- Rebuild chapters (optional max-bytes per part):
  - Default (~100k): `python3 scripts/build_zig_chapters.py`
  - Stricter (e.g., 50k): `python3 scripts/build_zig_chapters.py 50000`

The split generators automatically rewrite in-document anchors (e.g., `(#Something)`) to point back to the one-page file so cross-references continue to work across files.
