#!/usr/bin/env python3
"""Synthetic, public-data-only smoke tests for the private TotK embed generator."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().with_name("gen_embed.py")
spec = importlib.util.spec_from_file_location("gen_embed", SCRIPT)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class EmbedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.rewritten = root / "rewritten"
        self.exported = root / "exported"
        self.dest = root / "out"
        self.rewritten.mkdir()
        self.exported.mkdir()
        self.layout = root / "layout.json"
        meta = []
        self.originals = {}
        for i, name in enumerate(gen.MODULES):
            # Three synthetic images, not derived from Nintendo software.
            text = bytes([65 + i]) * 0x4000
            data = bytes([75 + i]) * 0x4000
            patch = bytes([85 + i]) * 0x2000
            original = text + data + patch
            self.originals[name] = original
            (self.rewritten / (name + ".patched.bin")).write_bytes(original)
            exported = bytearray(text)
            if name == "main":
                exported[8:12] = b"TEST"
            (self.exported / (name + ".x0.bin")).write_bytes(exported)
            meta.append({
                "name": name,
                "sha256": hashlib.sha256(original).hexdigest(),
                "size": len(original),
                "layout": {"TEXT_END": 0x3500, "PATCH_OFF": 0x8000},
            })
        self.layout.write_text(json.dumps(meta))
        self.meta = meta

    def test_three_segments_and_hashes(self):
        changes = gen.make_sections(self.layout, self.rewritten, self.exported, self.dest)
        self.assertEqual(changes, {"main": 1, "subsdk0": 0, "sdk": 0})
        asm = (self.dest / "ios_embed.S").read_text()
        header = (self.dest / "ios_embed.h").read_text()
        for name in gen.MODULES:
            self.assertIn("__TOTK" + name + "W,__img", asm)
            self.assertIn("__" + name + "x0", asm)
            self.assertIn("__" + name + "x1", asm)
            for kind, size in (("x0", 0x4000), ("w", 0x4000), ("x1", 0x4000)):
                segment = self.dest / f"{name}.{kind}.img"
                self.assertEqual(segment.stat().st_size, size)
                self.assertIn(hashlib.sha256(segment.read_bytes()).hexdigest(), header)
            self.assertEqual(
                (self.dest / f"{name}.x1.img").read_bytes(),
                bytes([85 + gen.MODULES.index(name)]) * 0x2000 + bytes(0x2000),
            )

    def test_macho_arm64_assembly_on_mac(self):
        import sys
        import subprocess
        if sys.platform != "darwin":
            self.skipTest("iPhoneOS assembler is available only on macOS")
        gen.make_sections(self.layout, self.rewritten, self.exported, self.dest)
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True
        ).strip()
        clang = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--find", "clang"], text=True
        ).strip()
        subprocess.run(
            [clang, "-arch", "arm64", "-isysroot", sdk,
             "-miphoneos-version-min=17.0", "-c",
             str(self.dest / "ios_embed.S"), "-o", str(self.dest / "ios_embed.o")],
            check=True,
        )
        self.assertGreater((self.dest / "ios_embed.o").stat().st_size, 0)

    def test_macho_ios_executable_link_on_mac(self):
        import sys
        import subprocess
        if sys.platform != "darwin":
            self.skipTest("iPhoneOS linker is available only on macOS")
        gen.make_sections(self.layout, self.rewritten, self.exported, self.dest)
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True
        ).strip()
        clang = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--find", "clang"], text=True
        ).strip()
        # This executable contains only synthetic sections, never game code.
        harness = self.dest / "section_harness.c"
        harness.write_text(
            '#include <mach-o/getsect.h>\n'
            '#include <mach-o/ldsyms.h>\n'
            'int main(void) { unsigned long n=0; '
            'return getsectiondata(&_mh_execute_header, "__TOTKX", '
            '"__mainx0", &n)==0 || n!=16384; }\n'
        )
        executable = self.dest / "synthetic-ios-runtime"
        subprocess.run([
            clang, "-arch", "arm64", "-isysroot", sdk,
            "-miphoneos-version-min=17.0",
            str(harness), str(self.dest / "ios_embed.S"),
            "-Wl,-segprot,__TOTKX,rx,rx",
            "-Wl,-segprot,__TOTKmainW,rw,rw",
            "-Wl,-segprot,__TOTKsubsdk0W,rw,rw",
            "-Wl,-segprot,__TOTKsdkW,rw,rw",
            "-o", str(executable),
        ], check=True)
        self.assertGreater(executable.stat().st_size, 0)
        segments = subprocess.check_output(["xcrun", "otool", "-l", str(executable)], text=True)
        for segment in ("__TOTKX", "__TOTKmainW", "__TOTKsubsdk0W", "__TOTKsdkW"):
            self.assertIn("segname " + segment, segments)
        self.assertIn("sectname __mainx0", segments)
        self.assertIn("sectname __sdkx1", segments)

    def test_tampered_module_rejected(self):
        target = self.rewritten / "sdk.patched.bin"
        raw = bytearray(target.read_bytes())
        raw[20] ^= 1
        target.write_bytes(raw)
        with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
            gen.make_sections(self.layout, self.rewritten, self.exported, self.dest)

    def test_missing_export_rejected(self):
        (self.exported / "main.x0.bin").unlink()
        with self.assertRaisesRegex(ValueError, "missing exported"):
            gen.make_sections(self.layout, self.rewritten, self.exported, self.dest)

    def test_unaligned_patch_rejected(self):
        self.meta[0]["layout"]["PATCH_OFF"] = 0x7000
        self.layout.write_text(json.dumps(self.meta))
        with self.assertRaisesRegex(ValueError, "incompatible"):
            gen.make_sections(self.layout, self.rewritten, self.exported, self.dest)


if __name__ == "__main__":
    unittest.main()
