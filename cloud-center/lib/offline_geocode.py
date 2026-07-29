"""Offline reverse geocoding — nearest city/town from bundled GeoNames data."""
from __future__ import annotations

import gzip
import logging
import math
import os
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

DATA_DIR = Path(__file__).resolve().parent.parent / "data"
BUNDLED_GZ = DATA_DIR / "geonames_cities1000.tsv.gz"
CACHE_FILE = (
    Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    / "cloud-center"
    / "geonames_cities1000.tsv.gz"
)

# ISO 3166-1 alpha-2 → common English name (subset; unknown codes shown as-is).
_COUNTRY_NAMES: dict[str, str] = {
    "GB": "United Kingdom",
    "US": "United States",
    "IE": "Ireland",
    "FR": "France",
    "DE": "Germany",
    "ES": "Spain",
    "IT": "Italy",
    "NL": "Netherlands",
    "BE": "Belgium",
    "AU": "Australia",
    "NZ": "New Zealand",
    "CA": "Canada",
    "JP": "Japan",
    "IN": "India",
    "PL": "Poland",
    "SE": "Sweden",
    "NO": "Norway",
    "DK": "Denmark",
    "FI": "Finland",
    "CH": "Switzerland",
    "AT": "Austria",
    "PT": "Portugal",
    "CZ": "Czechia",
}

# GeoNames admin1 codes for UK home nations.
_UK_ADMIN1: dict[str, str] = {
    "ENG": "England",
    "SCT": "Scotland",
    "WLS": "Wales",
    "NIR": "Northern Ireland",
}


@dataclass(frozen=True, slots=True)
class PlaceMatch:
    name: str
    admin1: str
    country: str
    latitude: float
    longitude: float
    distance_km: float

    @property
    def label(self) -> str:
        country_name = _COUNTRY_NAMES.get(self.country, self.country)
        region = _UK_ADMIN1.get(self.admin1, self.admin1) if self.admin1 else ""
        if region and region.lower() not in self.name.lower():
            return f"{self.name}, {region}, {country_name}"
        return f"{self.name}, {country_name}"


_grid: dict[tuple[int, int], list[tuple[float, float, str, str, str]]] | None = None
_loaded_path: Path | None = None


def data_available() -> bool:
    return _resolve_data_path() is not None


def _resolve_data_path() -> Path | None:
    if CACHE_FILE.is_file():
        return CACHE_FILE
    if BUNDLED_GZ.is_file():
        return BUNDLED_GZ
    return None


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlon / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _cell(lat: float, lon: float) -> tuple[int, int]:
    # ~0.5° cells — keeps each bucket small for fast nearest-neighbor search.
    return int(lat * 2), int(lon * 2)


def _load_grid() -> bool:
    global _grid, _loaded_path
    path = _resolve_data_path()
    if path is None:
        _grid = None
        _loaded_path = None
        return False
    if _grid is not None and _loaded_path == path:
        return True

    grid: dict[tuple[int, int], list[tuple[float, float, str, str, str]]] = {}
    try:
        with gzip.open(path, "rt", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("\t")
                if len(parts) < 5:
                    continue
                name, admin1, country, lat_s, lon_s = parts[:5]
                try:
                    lat, lon = float(lat_s), float(lon_s)
                except ValueError:
                    continue
                grid.setdefault(_cell(lat, lon), []).append(
                    (lat, lon, name, admin1, country)
                )
    except OSError as e:
        log.warning("Failed to load geonames data from %s: %s", path, e)
        _grid = None
        _loaded_path = None
        return False

    _grid = grid
    _loaded_path = path
    log.info("Loaded offline geonames index from %s (%d cells)", path, len(grid))
    return True


def lookup(latitude: float, longitude: float) -> PlaceMatch | None:
    """Return nearest city/town (population ≥ 1000 in GeoNames) without network access."""
    if not _load_grid() or _grid is None:
        return None

    best: PlaceMatch | None = None
    clat, clon = _cell(latitude, longitude)
    for dlat in (-1, 0, 1):
        for dlon in (-1, 0, 1):
            for plat, plon, name, admin1, country in _grid.get((clat + dlat, clon + dlon), ()):
                dist = _haversine_km(latitude, longitude, plat, plon)
                if best is None or dist < best.distance_km:
                    best = PlaceMatch(name, admin1, country, plat, plon, dist)
    return best


def format_place(latitude: float, longitude: float, accuracy_m: float = 0.0) -> str:
    """Human-readable place line for coordinates."""
    match = lookup(latitude, longitude)
    if match is None:
        if not data_available():
            return (
                f"{latitude:.5f}, {longitude:.5f}  "
                "(offline place data missing — re-run cloudyy install)"
            )
        return f"{latitude:.5f}, {longitude:.5f}"

    coord = f"{latitude:.5f}, {longitude:.5f}"
    acc = f"±{accuracy_m:.0f} m" if accuracy_m > 0 else ""
    if match.distance_km > 25 and acc:
        return f"{match.label}  ·  {coord}  ({acc}, ~{match.distance_km:.0f} km to town centre)"
    if acc:
        return f"{match.label}  ·  {coord}  ({acc})"
    return f"{match.label}  ·  {coord}"
