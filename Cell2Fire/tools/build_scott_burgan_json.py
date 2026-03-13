#!/usr/bin/env python3
"""Extract Table 7 from the Scott & Burgan PDF and emit structured JSON."""
from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

PDF_PATH = pathlib.Path("/Users/afnan/Desktop/40-Standard Fire Behavior Fuel Models.pdf")
OUTPUT_DIR = pathlib.Path(__file__).resolve().parent / "fuel_models"
JSON_PATH = OUTPUT_DIR / "scott_burgan_table7.json"
CSV_PATH = OUTPUT_DIR / "scott_burgan_table7.csv"
PAGE = 24

LINE_RE = re.compile(
    r"^(?P<code>[A-Z]{2}\d)\s+"
    r"(?P<dead1>\d+\.\d+)\s+(?P<dead10>\d+\.\d+)\s+(?P<dead100>\d+\.\d+)\s+"
    r"(?P<live_herb>\d+\.\d+)\s+(?P<live_wood>\d+\.\d+)\s+"
    r"(?P<model_type>\S+)\s+"
    r"(?P<sav_dead>\d+)\s+(?P<sav_live_herb>\d+)\s+(?P<sav_live_wood>\d+)\s+"
    r"(?P<depth>\d+\.\d+)\s+(?P<mext>\d+)\s+(?P<heat>\d+)"
)

def extract_table() -> str:
    cmd = ["pdftotext", "-layout", "-f", str(PAGE), "-l", str(PAGE), str(PDF_PATH), "-"]
    try:
        out = subprocess.check_output(cmd)
    except FileNotFoundError:
        cmd[0] = "/opt/homebrew/bin/pdftotext"
        out = subprocess.check_output(cmd)
    return out.decode("utf-8", errors="ignore")


def parse_table(text: str) -> dict[str, dict[str, float | str]]:
    data: dict[str, dict[str, float | str]] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or not line[:2].isalpha():
            continue
        match = LINE_RE.match(line)
        if not match:
            continue
        entry = match.groupdict()
        code = entry.pop("code")
        entry["model_type"] = entry["model_type"].lower()
        data[code] = {
            key: (float(value) if key not in {"model_type"} else value)
            for key, value in entry.items()
        }
    if len(data) != 40:
        raise RuntimeError(f"Expected 40 fuel models, parsed {len(data)}.\nLast text:\n{text}")
    return data


def main() -> None:
    text = extract_table()
    data = parse_table(text)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    JSON_PATH.write_text(json.dumps(data, indent=2, sort_keys=True))

    headers = [
        "code",
        "dead1",
        "dead10",
        "dead100",
        "live_herb",
        "live_wood",
        "model_type",
        "sav_dead",
        "sav_live_herb",
        "sav_live_wood",
        "depth",
        "mext",
        "heat",
    ]
    with CSV_PATH.open("w", encoding="utf-8") as f:
        f.write(",".join(headers) + "\n")
        for code, params in sorted(data.items()):
            row = [code] + [str(params[h]) if h != "model_type" else params[h] for h in headers[1:]]
            f.write(",".join(row) + "\n")

    print(f"Wrote {len(data)} models to {JSON_PATH} and {CSV_PATH}")


if __name__ == "__main__":
    sys.exit(main())
