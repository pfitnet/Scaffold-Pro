## Workflow — auto-merge into main (standing permission)

Read `HANDOFF.md` first; its section 2 is the workflow. The user has given
durable permission, which counts as asking for a PR: when a task is done,
commit, push, open a PR against `main` (pfitnet/Scaffold-Pro) and **merge it
straight away** (merge method "merge"), without asking. Hold only for red CI
or a merge conflict; fix it, then merge. If the branch's earlier PR was
already merged, restart the branch from `origin/main` and open a new PR.

## Skills

Design and motion skills are installed in `.claude/skills/` (from
`Leonxlnx/taste-skill` and `emilkowalski/skills`, tracked in
`skills-lock.json`). Use them for UI, animation and Swift work, keeping to the
look the user likes (HANDOFF.md section 3: calm, roomy, no flashing).

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
