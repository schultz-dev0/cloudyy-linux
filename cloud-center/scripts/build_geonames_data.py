#!/usr/bin/env python3
"""Build geonames_cities1000.tsv.gz for offline reverse geocoding (install-time)."""
from __future__ import annotations

import gzip
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

URL = "https://download.geonames.org/export/dump/cities1000.zip"
OUT = Path(__file__).resolve().parent.parent / "data" / "geonames_cities1000.tsv.gz"


def main() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {URL} …")
    with urllib.request.urlopen(URL, timeout=120) as resp:
        raw = resp.read()

    print("Extracting cities1000.txt …")
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        name = next(n for n in zf.namelist() if n.endswith("cities1000.txt"))
        text = zf.read(name).decode("utf-8")

    lines_out: list[str] = ["# name\tadmin1\tcountry\tlat\tlon"]
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) < 15:
            continue
        name = cols[1] or cols[2]
        lat, lon = cols[4], cols[5]
        country = cols[8]
        admin1 = cols[10]
        if not name or not lat or not lon:
            continue
        lines_out.append(f"{name}\t{admin1}\t{country}\t{lat}\t{lon}")

    print(f"Writing {len(lines_out) - 1} places → {OUT}")
    with gzip.open(OUT, "wt", encoding="utf-8") as fh:
        fh.write("\n".join(lines_out))
        fh.write("\n")

    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
