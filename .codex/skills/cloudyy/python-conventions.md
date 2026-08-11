# Python Conventions (Cloud Center backend, `cloud-center/`)

## Stated philosophy (project CLAUDE.md, quote directly)

- **Simplicity First** — "Minimum code that solves the problem. Nothing speculative... No abstractions for single-use code... If you write 200 lines and it could be 50, rewrite it."
- **Surgical Changes** — "Touch only what you must... Don't 'improve' adjacent code, comments, or formatting... Match existing style, even if you'd do it differently... Every changed line should trace directly to the user's request."
- **Goal-Driven Execution** — "Define success criteria. Loop until verified." E.g. "Fix the bug" → "Write a test that reproduces it, then make it pass."
- (From the backend's original implementation plan, still followed): constants defined once at module top; plain readable code over cleverness; small functions, early returns.

## Module structure (`lib/ccd/`)

One JSON-lines sidecar process, one file per concern, each module self-registers at import time:
- `protocol.py` — `METHODS: dict[str, Callable]` dispatch table, `register()`, `handle_line()`, `ok_response`/`error_response`.
- `model.py` — builds the page model from `config.yaml`.
- `actions.py` — `run_action` executes row commands via `subprocess` in worker threads.
- `keybinds.py` — thin QML-facing wrapper reusing `lib/keybind_manager_lua.py`'s functions (stated in its own module docstring).
- `state.py`, `watchers.py` — subscriptions / event-driven state pushes.
- `__main__.py` imports every submodule purely for registration side-effects (`# noqa: F401`), runs the stdin read-loop, calls each module's `shutdown()` in a `finally:` block.

Every ccd file opens with a docstring: `"""Cloud Center — lib/ccd/<name>.py\n<one-paragraph responsibility>"""`.

**Adding a new backend concern:** new file in `lib/ccd/`, opening docstring, register its methods in `__init__`/import-time side effect, import it (for side effects) from `__main__.py`.

## Naming

**Leading underscores on function names are used throughout current code** (`_stale_from_error`, `_thread_main`, `_fetch_layout`, `_entry_dict`). **Don't enforce the "no underscore" rule** — it doesn't reflect the actual codebase; match what's already there (leading underscore = private/internal helper, same as normal Python convention). 

**Leading underscores on function names** are the convention for all python code in thise repository.** (`_stale_from_error`, `_thread_main`, `_fetch_layout`, `_entry_dict`). Underscores exists for faster function name search in large codebases

## Type hints

Every file starts with `from __future__ import annotations` and uses PEP 585 modern generics (`dict[str, Callable]`, `list[dict]`, `X | None`) — never `typing.Dict`/`typing.Optional`. Match this exactly in new code.

## Testing

`unittest.TestCase`, run via pytest, not pytest-native fixtures/free functions:
```python
class ActionsTest(unittest.TestCase):
    def test_specific_behavior(self):
        ...
```
Naming: `test_ccd_<module>.py` mirrors `lib/ccd/<module>.py` 1:1. `test_<feature>_contract.py` tests page-model contracts; `test_<feature>_core.py` tests extracted core-logic modules. `tests/conftest.py` only does `sys.path` setup — no fixtures.

## Error handling / logging

Module-level logger in every file: `log = logging.getLogger(__name__)`. Narrow `try/except Exception` around subprocess/IO calls, non-fatal failures via `log.warning("...", exc)` with lazy `%s` formatting. Only the top-level dispatch loop (`protocol.py`'s `handle_line`) uses `log.exception(...)`, converting any handler exception into an `error_response` instead of crashing the process — individual modules should not swallow-and-crash-process; let `handle_line` be the single place that turns exceptions into responses.

## Comments / docstrings

Short module-header docstring stating purpose; function docstrings only when the behavior is non-obvious (e.g. explaining an exact formatting rule); inline `#` comments explain *why*, not *what* (e.g. explaining a fallback's rationale, not restating the code). No blanket "no comments" rule — comments are sparse and purposeful, not avoided outright.
