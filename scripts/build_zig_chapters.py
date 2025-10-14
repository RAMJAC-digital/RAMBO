#!/usr/bin/env python3
import re
import sys
from pathlib import Path


SRC = Path('docs/zig/0.15.1/zig-0.15.1.md')
BASE_OUT = Path('docs/zig/0.15.1')
CH_OUT = BASE_OUT / 'chapters'


SECTIONS_ORDER = [
    'Introduction',
    'Zig Standard Library',
    'Hello World',
    'Comments',
    'Values',
    'Zig Test',
    'Variables',
    'Integers',
    'Floats',
    'Operators',
    'Arrays',
    'Vectors',
    'Pointers',
    'Slices',
    'struct',
    'enum',
    'union',
    'opaque',
    'Blocks',
    'switch',
    'while',
    'for',
    'if',
    'defer',
    'unreachable',
    'noreturn',
    'Functions',
    'Errors',
    'Optionals',
    'Casting',
    'Zero Bit Types',
    'Result Location Semantics',
    'comptime',
    'Assembly',
    'Atomics',
    'Async Functions',
    'Builtin Functions',
    'Build Mode',
    'Single Threaded Builds',
    'Illegal Behavior',
    'Memory',
    'Compile Variables',
    'Compilation Model',
    'Zig Build System',
    'C',
    'WebAssembly',
    'Targets',
    'Style Guide',
    'Source Encoding',
    'Keyword Reference',
    'Appendix',
]


# Define chapters as tuples: (Chapter Title, [section titles to include])
CHAPTERS = [
    ("Introduction & Basics", [
        'Introduction', 'Zig Standard Library', 'Hello World', 'Comments', 'Values', 'Zig Test', 'Variables',
    ]),
    ("Numbers & Operators", [
        'Integers', 'Floats', 'Operators',
    ]),
    ("Arrays, Pointers & Slices", [
        'Arrays', 'Vectors', 'Pointers', 'Slices',
    ]),
    ("User Types", [
        'struct', 'enum', 'union', 'opaque',
    ]),
    ("Control Flow", [
        'Blocks', 'switch', 'while', 'for', 'if', 'defer', 'unreachable', 'noreturn',
    ]),
    ("Functions, Errors & Optionals", [
        'Functions', 'Errors', 'Optionals', 'Casting', 'Zero Bit Types',
    ]),
    ("Semantics & Compile-Time", [
        'Result Location Semantics', 'comptime',
    ]),
    ("Low-Level & Concurrency", [
        'Assembly', 'Atomics', 'Async Functions',
    ]),
    ("Builtins", [
        'Builtin Functions',
    ]),
    ("Build & Compilation", [
        'Build Mode', 'Single Threaded Builds', 'Illegal Behavior', 'Memory', 'Compile Variables', 'Compilation Model', 'Zig Build System',
    ]),
    ("Interop & Targets", [
        'C', 'WebAssembly', 'Targets',
    ]),
    ("Style & Appendix", [
        'Style Guide', 'Source Encoding', 'Keyword Reference', 'Appendix',
    ]),
]


def slugify(title: str) -> str:
    s = title.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip('-')
    return s or 'chapter'


def rewrite_links(text: str) -> str:
    # anchor-only links -> point to full doc
    text = re.sub(r"\]\(#", '](../zig-0.15.1.md#', text)
    text = re.sub(r"href=\"#", 'href="../zig-0.15.1.md#', text)
    return text


def load_sections():
    lines = SRC.read_text(encoding='utf-8').splitlines()
    pat = re.compile(r"^## \[(.+?)\]")
    headers = [(i, pat.match(l).group(1)) for i, l in enumerate(lines) if pat.match(l)]

    sections = {}
    order = []
    for idx, (start, title) in enumerate(headers):
        end = (headers[idx + 1][0] - 1) if (idx + 1) < len(headers) else (len(lines) - 1)
        sections[title] = (start, end)
        order.append(title)
    return lines, sections, order


def check_completeness(order):
    missing = [t for t in SECTIONS_ORDER if t not in order]
    if missing:
        print("Warning: some expected sections not found:", missing, file=sys.stderr)


def main():
    if not SRC.exists():
        print(f"Missing source: {SRC}", file=sys.stderr)
        sys.exit(1)

    CH_OUT.mkdir(parents=True, exist_ok=True)

    lines, sections, order = load_sections()
    check_completeness(order)

    # Build chapters
    index_lines = [
        "# Zig 0.15.1 Reference (Chapters)",
        "",
        "Split into larger, themed chapters for easier loading.",
        "",
        "- Full one-page reference: `zig-0.15.1.md`",
        "- Per-section split index: `README.md`",
        "",
        "## Chapters",
        "",
    ]

    for n, (ch_title, section_titles) in enumerate(CHAPTERS, start=1):
        # Gather section slices in order of the global doc
        ranges = []
        for t in section_titles:
            if t not in sections:
                print(f"Skipping missing section in chapter '{ch_title}': {t}", file=sys.stderr)
                continue
            s, e = sections[t]
            ranges.append((s, e))
        if not ranges:
            continue

        # Merge contiguous slices; ensure they are sorted by start
        ranges.sort(key=lambda x: x[0])
        merged = []
        cur_s, cur_e = ranges[0]
        for s, e in ranges[1:]:
            if s <= cur_e + 1:
                cur_e = max(cur_e, e)
            else:
                merged.append((cur_s, cur_e))
                cur_s, cur_e = s, e
        merged.append((cur_s, cur_e))

        # Build parts under a max size budget
        MAX_BYTES = int(sys.argv[1]) if len(sys.argv) > 1 else 100_000

        part_idx = 1
        part_buf = []
        def flush_part(buf):
            nonlocal part_idx
            title_suffix = f" (Part {part_idx})" if part_idx > 1 else ""
            header = []
            header.append("<!-- Auto-generated chapter from docs/zig/0.15.1/zig-0.15.1.md -->")
            header.append("[Back to chapters index](../CHAPTERS.md)  |  Split sections: ../README.md  |  Full reference: ../zig-0.15.1.md")
            header.append("")
            header.append(f"# {ch_title}{title_suffix}")
            header.append("")
            header.append("Included sections:")
            for t in section_titles:
                header.append(f"- {t}")
            header.append("")
            text = "\n".join(header + buf)
            text = rewrite_links(text)
            name = f"{n:02d}-{slugify(ch_title)}"
            if part_idx > 1:
                name += f"-part-{part_idx}"
            name += ".md"
            out_path = CH_OUT / name
            out_path.write_text(text + "\n", encoding='utf-8')
            # add to index
            index_lines.append(f"- [{n:02d}. {ch_title}{title_suffix}](chapters/{name})")
            part_idx += 1

        current_bytes = 0
        def split_large_block(body_lines):
            # Try split by '### [' subheaders, then by '#### ['; else fall back to ~200-line chunks
            def _split_by_heading(lines_in, marker):
                idxs = [i for i,l in enumerate(lines_in) if l.startswith(marker)]
                if not idxs:
                    return None
                parts = []
                for i, start in enumerate(idxs):
                    end = (idxs[i+1]-1) if i+1 < len(idxs) else (len(lines_in)-1)
                    parts.append(lines_in[start:end+1])
                return parts

            for marker in ('### [', '#### ['):
                parts = _split_by_heading(body_lines, marker)
                if parts:
                    return ["\n".join(p + [""]) for p in parts]

            # Fallback: chunk into ~200-line pieces
            chunks = []
            CHUNK = 200
            for i in range(0, len(body_lines), CHUNK):
                chunk = body_lines[i:i+CHUNK]
                chunks.append("\n".join(chunk + [""]))
            return chunks

        for s, e in merged:
            body = lines[s:e+1]
            while body and body[-1].strip() == '</div>':
                body.pop()
            block = "\n".join(body + [""])
            block_bytes = len(block.encode('utf-8'))
            if block_bytes > MAX_BYTES and not part_buf:
                # split within the section
                for sub in split_large_block(body):
                    sub_b = len(sub.encode('utf-8'))
                    if current_bytes + sub_b > MAX_BYTES and part_buf:
                        flush_part(part_buf)
                        part_buf = []
                        current_bytes = 0
                    part_buf.append(sub)
                    current_bytes += sub_b
                continue
            if current_bytes + block_bytes > MAX_BYTES and part_buf:
                flush_part(part_buf)
                part_buf = []
                current_bytes = 0
            part_buf.append(block)
            current_bytes += block_bytes

        if part_buf:
            flush_part(part_buf)

    # Write chapters index at 0.15.1 root
    (BASE_OUT / 'CHAPTERS.md').write_text("\n".join(index_lines) + "\n", encoding='utf-8')
    print(f"Wrote {len(CHAPTERS)} chapters to {CH_OUT}")


if __name__ == '__main__':
    main()
