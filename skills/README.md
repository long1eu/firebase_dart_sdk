# Agent Skills

`cloud-firestore-dart/` is an Agent Skill for coding agents that write or review Dart or Flutter
code using `cloud_firestore_dart`, `firebase_app_dart` and `firebase_auth_providers_dart`. It
gives the agent the imports, the setup in the right order, the FlutterFire and JS SDK names
mapped to this client's names, the rules that code against this client must follow, and how to
check the result against the Firestore emulator.

The folder stands alone: `SKILL.md` is the entry point, `reference/` holds the longer material
(the full name map, setup templates, writes, offline behaviour and errors), and every link out of
it points to this repository on GitHub.

## Install

Copy the whole folder, not only `SKILL.md`:

- for one project: into `.claude/skills/` of that project, giving
  `.claude/skills/cloud-firestore-dart/SKILL.md`;
- for every project of a user: into `~/.claude/skills/`.

For example, from a checkout of this repository:

```shell
mkdir -p /path/to/your/project/.claude/skills
cp -R skills/cloud-firestore-dart /path/to/your/project/.claude/skills/
```

These are the skill locations of Claude Code. Other agents that read Agent Skills may look
elsewhere; the skill was not tried with them.

The skill describes version 0.1.x of the packages. When you update the packages, copy the skill
again from the matching version of this repository.
