# Team config

human: {{HUMAN}}
project: {{PROJECT_NAME}}

models:
  product-owner: claude (opus)
  architect: claude (opus)
  coder: claude (sonnet)
  reviewer: claude (sonnet)

merge: human

team: .claude/skills/agent-team @ {{SKILL_VERSION}}
<!-- upgrade with /agent-team upgrade, or: git submodule update --remote .claude/skills/agent-team -->

Per-project role overrides: drop a file in `.team/roles/<role>.md` and the launcher uses it instead of the submodule's.
