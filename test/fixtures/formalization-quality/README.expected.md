# Expected behavior

At the acceptance-baseline stage:

- all Lean fixtures are source-only and do not require a repository-wide Lean package yet;
- the three `*Bad.lean` fixtures are expected to be accepted by ordinary Lean once the native package is introduced, but rejected by formalization lint;
- `HonestScaffold.lean` is expected to pass because it advertises only what it proves;
- later PRs must preserve the diagnostic identifiers recorded in `expected-results.edn`.
