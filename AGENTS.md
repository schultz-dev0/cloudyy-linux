# AGENTS.md

## Superpowers depth — ask before loading skills

At the start of each non-trivial task, ask which Superpowers depth to use
**before reading or invoking any Superpowers skill, exploring, planning, or
implementing**. This gate takes precedence over automatic Superpowers triggers,
including `using-superpowers` and its instruction to load skills before responding.

Keep the question short:

1. **Full Superpowers** — use the applicable full workflows and approval gates.
2. **Partial + visual** — lightweight brainstorming and design approval in chat;
   visual companion when useful; concise plan, then implement after approval.
3. **Partial, no spec or visual** — explore, ask only key questions, make a concise
   plan, then implement after approval.
4. **Skip Superpowers** — proceed directly; investigate bugs and verify material
   changes, but do not read or invoke any Superpowers skills.

Accept a number or name. Ask once per task; an explicit selection or request to
skip the workflow already counts. Do not ask for trivial one-shot tasks. For
levels 2–3, skip spec files and spec commits, and load only skills needed for the
selected lightweight workflow; do not load the full pipeline merely to skip it.
User instructions override skill requirements. Never create commits in this repo.

## Repo coordination

Before you touch this repo, read the agent charter:

    ~/MyLife/07 - Projects/Cloudyy/Agents/Charter.md

That directory is the shared coordination space for every agent working on Cloudyy —
parallel sessions, sessions days apart, subagents, and other tools (Codex, Cursor).
Start there to find out what is in flight, what another session has claimed, and why
past decisions went the way they did. Leave something behind when you finish.

Two rules from the charter, repeated here because they are the ones that break things:

- Agent coordination notes go in that directory and nowhere else in the vault.
- Never rewrite a file another session may be writing — append with `>>`, or create a
  new file.

Repo conventions (branch strategy, theming system, install layout) are in `~/CLAUDE.md`.
