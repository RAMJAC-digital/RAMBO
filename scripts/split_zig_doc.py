#!/usr/bin/env python3
import re
import sys
from pathlib import Path


SRC = Path('docs/zig/0.15.1/zig-0.15.1.md')
OUT_DIR = Path('docs/zig/0.15.1')


def slugify(title: str) -> str:
    # lower, replace non-alnum with '-', collapse dashes
    s = title.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip('-')
    if not s:
        s = 'section'
    return s


def rewrite_links(text: str) -> str:
    # rewrite anchor-only links to point to local full doc in same dir
    text = re.sub(r"\]\(#", '](zig-0.15.1.md#', text)
    text = re.sub(r"href=\"#", 'href="zig-0.15.1.md#', text)
    return text


def main():
    if not SRC.exists():
        print(f"Source not found: {SRC}", file=sys.stderr)
        sys.exit(1)

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    lines = SRC.read_text(encoding='utf-8').splitlines()

    # find top-level sections: lines starting with '## ['
    headers = []  # list of (idx, title)
    pat = re.compile(r"^## \[(.+?)\]")
    for i, line in enumerate(lines):
        m = pat.match(line)
        if m:
            headers.append((i, m.group(1)))

    if not headers:
        print("No top-level sections found", file=sys.stderr)
        sys.exit(1)

    # build sections with ranges
    sections = []
    for j, (start_idx, title) in enumerate(headers):
        end_idx = (headers[j + 1][0] - 1) if (j + 1) < len(headers) else (len(lines) - 1)
        sections.append((start_idx, end_idx, title))

    # write each section
    index_lines = [
        "# Zig 0.15.1 Reference (Split)",
        "", 
        "This is a split, easier-to-browse version of the one-page reference.",
        "", 
        "- Full one-page reference: `zig-0.15.1.md`",
        "",
        "## Sections",
        "",
    ]

    for idx, (start, end, title) in enumerate(sections, start=1):
        slug = slugify(title)
        filename = f"{idx:02d}-{slug}.md"
        out_path = OUT_DIR / filename

        body = lines[start:end+1]

        # Trim stray closing of the top-level wrapper if present at end of this slice
        while body and body[-1].strip() == '</div>':
            body.pop()

        content = []
        content.append(f"<!-- Extracted from docs/zig/0.15.1/zig-0.15.1.md; section: {title} -->")
        content.append("[Back to index](README.md)  |  Full reference: zig-0.15.1.md")
        content.append("")
        content.extend(body)

        text = "\n".join(content) + "\n"
        text = rewrite_links(text)
        out_path.write_text(text, encoding='utf-8')

        index_lines.append(f"- [{idx:02d}. {title}]({filename})")

    # write index README
    (OUT_DIR / 'README.md').write_text("\n".join(index_lines) + "\n", encoding='utf-8')

    print(f"Wrote {len(sections)} sections to {OUT_DIR}")


if __name__ == '__main__':
    main()
