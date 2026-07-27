# Formalization quality acceptance fixtures

These fixtures intentionally separate Lean compilation from semantic adequacy.

The `*Bad.lean` files are expected to compile as ordinary Lean examples while failing future ZIL formalization lint for precise, fixture-specific reasons recorded in `expected-results.edn`.

They establish the first non-negotiable acceptance property for the Lean-native work:

> A file does not satisfy its advertised formalization scope merely because its Lean declarations compile.

Later PRs will add honest scaffold fixtures and wire these expectations into executable lint tests.
