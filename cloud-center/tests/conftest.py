"""Make the project root importable for all tests (one place, not per-file)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
