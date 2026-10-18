#!/usr/bin/env python3
"""Produce local, page-aligned Mach-O image sections for TotK's iOS loader.

This tool takes PRIVATE output from the user's verified Mac build. It never
downloads games or keys and must never be invoked with CI secrets. All outputs
are derived from game executables: DO NOT COMMIT or upload them.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

PAGE = 0x4000
MODULES = ("main", "subsdk0", "sdk")
CHUNK = 1024 * 1024


def rounded(value: int) -> int:
    return (value + PAGE - 1) & ~(PAGE - 1)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(CHUNK), b""):
            h.update(chunk)
    return h.hexdigest()


def section_file(source: Path, start: int, size: int, target: Path) -> str:
    """Copy a bounded file range and pad to 16 KiB without modifying source."""
    assert start >= 0 and size > 0
    h = hashlib.sha256()
    with source.open("rb") as inp, target.open("wb") as out:
        inp.seek(start)
        left = size
        while left:
            chunk = inp.read(min(left, CHUNK))
            if not chunk:
                raise ValueError(f"short input {source}")
            out.write(chunk)
            h.update(chunk)
            left -= len(chunk)
        padding = rounded(size) - size
        if padding:
            z = bytes(padding)
            out.write(z)
            h.update(z)
    return h.hexdigest()


def incbin(path: Path) -> str:
    s = str(path.resolve())
    if "\n" in s or "\r" in s:
        raise ValueError("Newlines in image path are not supported")
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def verify_export(original: Path, exported: Path, count: int, name: str) -> int:
    if exported.stat().st_size != count:
        raise ValueError(f"{name}: exported patched text length mismatch")
    differences = 0
    with original.open("rb") as source, exported.open("rb") as patch:
        remaining = count
        while remaining:
            n = min(CHUNK, remaining)
            a, b = source.read(n), patch.read(n)
            if len(a) != n or len(b) != n:
                raise ValueError(f"{name}: incomplete exported image")
            # Text modifications must be whole ARM64 instructions.
            differences += sum(a[i:i+4] != b[i:i+4] for i in range(0, n, 4))
            remaining -= n
    return differences


def make_sections(layout_file: Path, rewritten: Path, exported: Path, dest: Path) -> dict[str, int]:
    modules = json.loads(layout_file.read_text())
    if (not isinstance(modules, list)
            or [m.get("name") for m in modules if isinstance(m, dict)] != list(MODULES)
            or len(modules) != 3):
        raise ValueError("runtime-layout.json must contain main, subsdk0, sdk, in that order")
    dest.mkdir(parents=True, exist_ok=True)
    rows = []
    assembly = [
        "/* PRIVATE! Generated using local user game files; never commit this output. */",
        "/* Section names/layout are consumed by runtime/loader.c on iOS. */",
    ]
    counts: dict[str, int] = {}
    for m in modules:
        name = m["name"]
        image = rewritten / f"{name}.patched.bin"
        x0_in = exported / f"{name}.x0.bin"
        length = m["size"]
        meta = m["layout"]
        end = meta["TEXT_END"]
        patch = meta["PATCH_OFF"]
        original_hash = m["sha256"]
        if not isinstance(length, int) or not isinstance(end, int) or not isinstance(patch, int):
            raise ValueError(f"{name}: invalid integer offsets")
        x0len = rounded(end)
        endlen = rounded(length)
        if not (end > 0 and x0len < patch < length and patch % PAGE == 0
                and x0len % PAGE == 0 and patch < endlen):
            raise ValueError(f"{name}: incompatible 16 KiB module sections")
        if not isinstance(original_hash, str) or not re.fullmatch(r"[a-f0-9]{64}", original_hash):
            raise ValueError(f"{name}: missing verified original hash")
        if not image.is_file() or image.stat().st_size != length:
            raise ValueError(f"{name}: missing or wrong-size verified image")
        if digest(image) != original_hash:
            raise ValueError(f"{name}: SHA256 mismatch against private runtime layout")
        if not x0_in.is_file():
            raise ValueError(f"{name}: missing exported text (run TOTK_EXPORT_IOS locally)")

        counts[name] = verify_export(image, x0_in, x0len, name)
        x0_out = dest / f"{name}.x0.img"
        w_out = dest / f"{name}.w.img"
        x1_out = dest / f"{name}.x1.img"
        x0_hash = section_file(x0_in, 0, x0len, x0_out)
        w_hash = section_file(image, x0len, patch - x0len, w_out)
        x1_hash = section_file(image, patch, length - patch, x1_out)
        sizes = (x0len, patch - x0len, endlen - patch)
        for kind, section, seg, name2, size in (
            ("x0", x0_out, "__TOTKX", f"__{name}x0", sizes[0]),
            ("w", w_out, f"__TOTK{name}W", "__img", sizes[1]),
            ("x1", x1_out, "__TOTKX", f"__{name}x1", sizes[2]),
        ):
            if section.stat().st_size != size:
                raise ValueError(f"{name}: unexpected {kind} output size")
            # Labels keep generated sections live even if ld uses dead stripping.
            assembly += [
                f".section {seg},{name2},regular" + (",pure_instructions" if kind != "w" else ""),
                ".p2align 14",
                f".globl _totk_embed_{name}_{kind}",
                f"_totk_embed_{name}_{kind}:",
                f".incbin {incbin(section)}",
            ]
        rows.append((name, x0_hash, w_hash, x1_hash))
    assembly.append(".subsections_via_symbols")
    (dest / "ios_embed.S").write_text("\n".join(assembly) + "\n")
    c = [
        "/* PRIVATE derived game metadata. Never commit or upload this file. */",
        "#pragma once",
        "typedef struct {const char *name, *x0, *w, *x1;} IosEmbed;",
        "static const IosEmbed ios_embed[] = {",
    ]
    for name, x0, w, x1 in rows:
        c.append(f'    {{"{name}", "{x0}", "{w}", "{x1}"}},')
    c.append("};")
    (dest / "ios_embed.h").write_text("\n".join(c) + "\n")
    return counts


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--layout", required=True, type=Path, help="private runtime-layout.json")
    p.add_argument("--rewritten", required=True, type=Path, help="private v0/v112/v143 rewritten modules")
    p.add_argument("--exported", required=True, type=Path, help="private TOTK_EXPORT_IOS x0 output folder")
    p.add_argument("--out", required=True, type=Path, help="PRIVATE output directory outside tracked source")
    a = p.parse_args()
    try:
        counts = make_sections(a.layout, a.rewritten, a.exported, a.out)
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print("PRIVATE embeds generated; changed instruction words per module:")
    for name, changed in counts.items():
        print(f"  {name}: {changed}")
    print("Outputs: ios_embed.S and ios_embed.h; requires separate signed iOS link.")
    print("Never commit or upload these generated files or derived binaries.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
