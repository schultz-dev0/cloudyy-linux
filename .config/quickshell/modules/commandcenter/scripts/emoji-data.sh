#!/bin/bash
# Emits rofimoji's bundled emoji CSV data as JSON lines: {"char":...,"name":...,"keywords":...}
set -euo pipefail

data_dir=$(python3 -c "import picker, os; print(os.path.join(os.path.dirname(picker.__file__), 'data'))" 2>/dev/null) || exit 0

exec python3 -c '
import glob, json, re, sys

pattern = re.compile(r"^(\S+) (.+) <small>\((.*)\)</small>$")

for path in sorted(glob.glob(sys.argv[1] + "/emojis_*.csv")):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            m = pattern.match(line)
            if not m:
                continue
            char, name, keywords = m.group(1), m.group(2), m.group(3)
            print(json.dumps({"char": char, "name": name, "keywords": keywords}))
' "$data_dir"
