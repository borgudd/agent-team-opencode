# Team config

Each role runs in its own clone, in its own terminal. Launch with `./team <role>` from the workspace, or `.team/bin/<role>` from inside a clone.

models:
  product-owner: claude-fable-5-1
  architect: claude-fable-5-1
  coder: opus
  reviewer: codex (GPT, high reasoning effort)

merge: human

scaffolded-by: agent-team {{SKILL_VERSION}}
