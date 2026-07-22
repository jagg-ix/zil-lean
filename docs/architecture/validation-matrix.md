# Validation matrix

| Area | Positive | Negative | Round trip | Cross-boundary |
|---|---|---|---|---|
| Relation parsing | canonical fact/rule | malformed or unbound variable | parse/emit/parse | Clojure and Lean IR equality |
| Embedded scanning | stable `self` attachment | missing target | scan/emit/rescan | embedded and native equality |
| Rule trust | certified rule accepted | graph rule used as proof | serialize/reload trust | runtime and Lean trust parity |
| Formalization contracts | honest scaffold | misleading advertised scope | contract emit/reload | scanner and Lean reflection agreement |
| Agent recovery | current context | stale contract revision | snapshot replay | API and CLI decision parity |

The first PR supplies baseline fixtures and specifications. Later PRs must make the corresponding rows executable without weakening expected failure codes.
