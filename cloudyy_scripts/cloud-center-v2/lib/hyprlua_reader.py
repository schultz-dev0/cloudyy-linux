"""
Cloud Center — lib/hyprlua_reader.py

Best-effort reader for the Lua-syntax Hyprland config patterns:
  hl.window_rule({...}), hl.layer_rule({...}),
  hl.exec_once("..."), hl.exec_cmd("..."), hl.env("...", "..."),
  including hl.exec_* calls nested inside hl.on("hyprland.start", function() ... end).

Not a general Lua parser. It does brace/paren counting (skipping strings and
line comments) and a minimal key/value extractor for table literals. Patterns
it can't decode (e.g. `scripts .. "/x.sh"`) come out as the raw expression
text — good enough for a read-only "what's currently active" view.
"""
from __future__ import annotations

import json
import re
from typing import Iterator


# ── Tokenizer-ish helpers ──────────────────────────────────────────────────────

def _skip_string(text: str, i: int) -> int:
    """`i` points at the opening quote. Returns index just past the close."""
    quote = text[i]
    i += 1
    while i < len(text):
        c = text[i]
        if c == '\\' and i + 1 < len(text):
            i += 2
            continue
        if c == quote:
            return i + 1
        i += 1
    return i


def _skip_line_comment(text: str, i: int) -> int:
    """`i` points at the first `-` of `--`. Returns index of next newline or EOF."""
    nl = text.find('\n', i)
    return len(text) if nl == -1 else nl


def _find_matching(text: str, open_idx: int, open_ch: str, close_ch: str) -> int:
    """
    Return the index of the `close_ch` that pairs with `text[open_idx]`,
    skipping over strings and line comments. -1 if not found.
    """
    depth = 0
    i = open_idx
    while i < len(text):
        c = text[i]
        if c in ('"', "'"):
            i = _skip_string(text, i)
            continue
        if c == '-' and i + 1 < len(text) and text[i + 1] == '-':
            i = _skip_line_comment(text, i)
            continue
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _iter_calls(text: str, fn_name: str) -> Iterator[str]:
    """Yield the inside of each `hl.<fn_name>(...)` call."""
    needle = f'hl.{fn_name}('
    i = 0
    while True:
        j = text.find(needle, i)
        if j == -1:
            return
        # require word boundary before "hl."
        if j > 0 and (text[j - 1].isalnum() or text[j - 1] == '_'):
            i = j + 1
            continue
        open_paren = j + len(needle) - 1
        close_paren = _find_matching(text, open_paren, '(', ')')
        if close_paren == -1:
            return
        yield text[open_paren + 1:close_paren]
        i = close_paren + 1


# ── Value coercion ─────────────────────────────────────────────────────────────

_BOOL_RE = re.compile(r'^(true|false)$')
_NUM_RE = re.compile(r'^-?(?:\d+\.\d+|\d+|\.\d+)$')


def _lua_string(text: str, i: int) -> tuple[str | None, int]:
    """Parse a "..." or '...' string. Returns (value, next_idx) or (None, i)."""
    if i >= len(text) or text[i] not in ('"', "'"):
        return None, i
    end = _skip_string(text, i)
    raw = text[i:end]
    try:
        if raw.startswith('"'):
            return json.loads(raw), end
        # single-quoted: convert to JSON form
        return json.loads('"' + raw[1:-1].replace('"', '\\"') + '"'), end
    except json.JSONDecodeError:
        return raw[1:-1], end


def _coerce(raw: str) -> str:
    """Stringify a top-level Lua value for the dataclass effects/matchers dict."""
    raw = raw.strip().rstrip(',').strip()
    if not raw:
        return ''
    if raw.startswith(('"', "'")):
        val, _ = _lua_string(raw, 0)
        return val if val is not None else raw
    if _BOOL_RE.match(raw):
        return 'on' if raw == 'true' else 'off'
    if _NUM_RE.match(raw):
        return raw
    return raw  # unresolved expression — show as-is


# ── Table parsing ──────────────────────────────────────────────────────────────

def _parse_table(inner: str) -> dict[str, str | dict[str, str]]:
    """
    Parse `key = value, key = value, ...` from the body of a `{ ... }` block.
    Nested `{ ... }` become a dict. Anything we don't understand → raw text.
    """
    out: dict[str, str | dict[str, str]] = {}
    pairs = _split_top_commas(inner)
    for pair in pairs:
        if '=' not in pair:
            continue
        key, _, val = pair.partition('=')
        key = key.strip()
        val = val.strip()
        if not key or not key.replace('_', '').replace('-', '').isalnum():
            continue
        if val.startswith('{') and val.endswith('}'):
            nested = _parse_table(val[1:-1])
            out[key] = {k: v for k, v in nested.items() if isinstance(v, str)}
        else:
            out[key] = _coerce(val)
    return out


def _split_top_commas(text: str) -> list[str]:
    """Split on commas not inside strings, braces, or parens."""
    parts: list[str] = []
    depth_brace = depth_paren = 0
    start = 0
    i = 0
    while i < len(text):
        c = text[i]
        if c in ('"', "'"):
            i = _skip_string(text, i)
            continue
        if c == '-' and i + 1 < len(text) and text[i + 1] == '-':
            i = _skip_line_comment(text, i)
            continue
        if c == '{':
            depth_brace += 1
        elif c == '}':
            depth_brace -= 1
        elif c == '(':
            depth_paren += 1
        elif c == ')':
            depth_paren -= 1
        elif c == ',' and depth_brace == 0 and depth_paren == 0:
            parts.append(text[start:i])
            start = i + 1
        i += 1
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


# ── Public API ─────────────────────────────────────────────────────────────────
#
# Returns plain dicts/tuples to keep this module decoupled from the dataclasses
# in rules_startup_page. The caller adapts them.

def parse_window_rules(text: str) -> list[dict]:
    """Each entry: {'name': str, 'matchers': [(key, val), ...], 'effects': {k: v}}."""
    results = []
    for inner in _iter_calls(text, 'window_rule'):
        inner = inner.strip().strip('{}').strip()
        table = _parse_table(inner)
        name = str(table.pop('name', ''))
        match = table.pop('match', None)
        matchers: list[tuple[str, str]] = []
        if isinstance(match, dict):
            for k, v in match.items():
                matchers.append((f'match:{k}', str(v)))
        effects = {k: str(v) for k, v in table.items() if not isinstance(v, dict)}
        results.append({'name': name, 'matchers': matchers, 'effects': effects})
    return results


def parse_layer_rules(text: str) -> list[dict]:
    """Each entry: {'name': str, 'namespace': str, 'effects': {k: v}}."""
    results = []
    for inner in _iter_calls(text, 'layer_rule'):
        inner = inner.strip().strip('{}').strip()
        table = _parse_table(inner)
        name = str(table.pop('name', ''))
        match = table.pop('match', None)
        namespace = ''
        if isinstance(match, dict):
            namespace = str(match.get('namespace', ''))
        effects = {k: str(v) for k, v in table.items() if not isinstance(v, dict)}
        results.append({'name': name, 'namespace': namespace, 'effects': effects})
    return results


def parse_autostart(text: str) -> list[dict]:
    """Each entry: {'command': str, 'exec_once': bool}. Picks up both top-level
    and hl.exec_*('cmd') nested inside hl.on(..., function() ... end) blocks."""
    results = []
    for fn_name, exec_once in (('exec_once', True), ('exec_cmd', False)):
        for inner in _iter_calls(text, fn_name):
            command = _extract_first_string_or_raw(inner)
            if command:
                results.append({'command': command, 'exec_once': exec_once})
    return results


def parse_env_vars(text: str) -> list[dict]:
    """Each entry: {'name': str, 'value': str}."""
    results = []
    for inner in _iter_calls(text, 'env'):
        parts = _split_top_commas(inner)
        if len(parts) < 2:
            continue
        name = _extract_first_string_or_raw(parts[0])
        value = _extract_first_string_or_raw(parts[1])
        if name:
            results.append({'name': name, 'value': value})
    return results


def _extract_first_string_or_raw(text: str) -> str:
    """Return the first string literal's content, or the trimmed raw expression
    if it's not a simple string."""
    text = text.strip().rstrip(',').strip()
    if text.startswith(('"', "'")):
        val, _ = _lua_string(text, 0)
        return val if val is not None else text
    return text
