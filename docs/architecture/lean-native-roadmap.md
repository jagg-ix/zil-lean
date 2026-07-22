# Lean-native roadmap

The Lean-native implementation will be delivered as a sequence of small pull requests with executable acceptance criteria.

## Phase 1: establish measurable semantics

1. Record the current architecture and reuse boundaries.
2. Add intentionally weak formalization fixtures and honest scaffold fixtures.
3. Define the canonical relational IR expected from legacy `.zc`, embedded comments, and future Lean-native syntax.

## Phase 2: native Lean frontend

1. Add a Lake package and core Lean AST.
2. Add theorem-shaped relation and rule syntax.
3. Add relation profiles and endpoint validation.
4. Persist facts, rules, and declaration metadata through Lean environment extensions.

## Phase 3: querying and certified reasoning

1. Add native query, check, and expansion commands.
2. Separate graph rules from kernel-certified rules.
3. Preserve derivation provenance and trust classes.

## Phase 4: formalization quality and agent recovery

1. Add file contracts and theorem-intent declarations.
2. Compare advertised scope with actual Lean declarations.
3. Detect documentation overclaims and silent scope weakening.
4. Connect existing context, lease, checkpoint, drift, and action-safety mechanisms to formalization contracts.

## Global constraints

- Lean compilation alone is not evidence that a formalization does what its file name or documentation claims.
- New native syntax and legacy syntax must lower to the same canonical IR.
- Graph-derived facts must never be promoted silently to kernel-checked proof.
- Every blocking diagnostic must have a dedicated negative fixture.
