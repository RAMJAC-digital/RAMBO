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
    pattern = re.compile(r"DEFINE\s+([^,\s]+)(?:\s*\(([^)]*)\))?\s*,?<", re.MULTILINE)
    for match in pattern.finditer(source):
        name = match.group(1)
        params_raw = match.group(2)
        params_list: List[str] = []
        if params_raw:
            params_list = [p.strip() for p in params_raw.split(',') if p.strip()]

        body_start = source.find('<', match.end())
        if body_start == -1:
            continue
        idx = body_start + 1
        depth = 1
        body_chars: List[str] = []
        while idx < len(source) and depth > 0:
            ch = source[idx]
            if ch == '<':
                depth += 1
                body_chars.append(ch)
            elif ch == '>':
                depth -= 1
                if depth > 0:
                    body_chars.append(ch)
            else:
                body_chars.append(ch)
            idx += 1
        body = ''.join(body_chars).rstrip('\n')
        yield MacroDefinition(name=name, parameters=params_list, body=body)


def analyse_macros(path: Path) -> list[MacroDefinition]:
    source = path.read_text()
    macros = list(_iter_macros(source))
    for macro in macros:
        usage_pattern = re.compile(rf"\b{re.escape(macro.name)}\b")
        macro.usages = len(usage_pattern.findall(source)) - 1  # subtract definition occurrence
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
