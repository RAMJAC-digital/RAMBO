from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, List


@dataclass
class MacroDefinition:
    name: str
    parameters: List[str]
    body: str
    usages: int = 0


def _iter_macros(source: str) -> Iterator[MacroDefinition]:
    pattern = re.compile(r"DEFINE\s+([^\s(,]+)(?:\s*\(([^)]*)\))?\s*,?\s*<", re.MULTILINE)
    for match in pattern.finditer(source):
        name = match.group(1)
        params_raw = match.group(2)
        params_list: List[str] = []
        if params_raw:
            params_list = [p.strip() for p in params_raw.split(',') if p.strip()]

        idx = match.end()
        depth = 1
        while idx < len(source) and depth > 0:
            ch = source[idx]
            if ch == '<':
                depth += 1
            elif ch == '>':
                depth -= 1
            idx += 1

        body = source[match.end(): idx - 1 if depth == 0 else idx]
        yield MacroDefinition(name=name, parameters=params_list, body=body.strip('\n'))


def analyse_macros(path: Path) -> list[MacroDefinition]:
    source = path.read_text()
    macros = list(_iter_macros(source))
    for macro in macros:
        usage_pattern = re.compile(rf"\b{re.escape(macro.name)}\b")
        count = len(usage_pattern.findall(source))
        macro.usages = max(count - 1, 0)  # subtract definition occurrence
    return macros


def write_manifest(macros: list[MacroDefinition], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    data = [
        {
            "name": macro.name,
            "parameters": macro.parameters,
            "lines": macro.body.count('\n') + 1 if macro.body else 0,
            "usages": macro.usages,
        }
        for macro in macros
    ]
    output.write_text(json.dumps(data, indent=2))


__all__ = ["analyse_macros", "write_manifest", "MacroDefinition"]
