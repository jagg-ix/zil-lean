# ZIL Domain Projects

This directory contains domain-specific project packs that are built on top of
ZIL core semantics.

Purpose:

- keep reusable language/runtime in top-level `lib/`, `src/`, `spec/`
- keep problem-specific implementations isolated under `projects/<name>/`
- make ownership and blast radius explicit for domain logic changes

Current project packs:

- none checked in currently; add new packs under `projects/<name>/`

Recommended boundaries:

- `projects/<name>/lib` : project DSL/macros/rules (domain-specific)
- `projects/<name>/models` : scenarios and concrete instances
- `projects/<name>/plugins` : optional variant packs
- `projects/<name>/docs` : project-specific operational notes
