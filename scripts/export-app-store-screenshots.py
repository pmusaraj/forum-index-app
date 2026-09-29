#!/usr/bin/env python3
"""Export named XCTest screenshot attachments as opaque App Store PNGs.

Usage: python3 scripts/export-app-store-screenshots.py <result.xcresult> iphone|ipad
Requires Pillow (python3 -m pip install Pillow).
"""

import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PIL import Image


def main():
    result, device = sys.argv[1:]
    expected_size = {"iphone": (1320, 2868), "ipad": (2064, 2752)}[device]
    output_size = {"iphone": (1242, 2688), "ipad": (2064, 2752)}[device]
    root = Path(__file__).resolve().parents[1] / "app-store-screenshots" / device
    captures = {}
    with tempfile.TemporaryDirectory() as temporary:
        subprocess.run([
            "xcrun", "xcresulttool", "export", "attachments", "--path", result,
            "--output-path", temporary,
        ], check=True)
        directory = Path(temporary)
        for test in json.loads((directory / "manifest.json").read_text()):
            for attachment in test["attachments"]:
                match = re.match(r"appstore-(light|dark)-(\d{2}-[a-z]+)_",
                                 attachment["suggestedHumanReadableName"])
                if not match:
                    continue
                appearance, name = match.groups()
                with Image.open(directory / attachment["exportedFileName"]) as image:
                    if image.size != expected_size:
                        raise ValueError(f"Unexpected dimensions: {image.size}")
                    capture = image.convert("RGB")
                    if capture.size != output_size:
                        capture = capture.resize(output_size, Image.Resampling.LANCZOS)
                    captures[(appearance, name)] = capture
        if len(captures) != 10:
            raise ValueError(f"Expected 10 captures for {device}, got {len(captures)}")
        for (appearance, name), image in captures.items():
            destination = root / appearance / f"{name}.png"
            destination.parent.mkdir(parents=True, exist_ok=True)
            image.save(destination, optimize=True)
            print(destination.relative_to(root.parent))


if __name__ == "__main__":
    main()
