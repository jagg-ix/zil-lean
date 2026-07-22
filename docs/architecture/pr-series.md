# Planned pull-request series

1. Acceptance baseline and architecture inventory.
2. Canonical relational IR shared by legacy, embedded, and Lean-native frontends.
3. Native Lean package and Lake build.
4. Theorem-shaped Lean relation and rule syntax.
5. Typed relation profiles and endpoint validation.
6. Persistent Lean environment extensions.
7. Lean declaration attributes.
8. Native query, check, and expansion commands.
9. Certified rules separated from graph rules.
10. Formalization contract DSL.
11. Formalization lint and coverage reports.
12. Agent context and recovery integration.
13. Embedded/native parity and migration tooling.
14. Executable Lean-user documentation.

Each PR must preserve existing Clojure tests and add positive, negative, round-trip, and cross-boundary parity tests where applicable.
