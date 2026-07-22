# Native Lean CLI

The `zil` executable operates directly on canonical Lean `ExchangeEnvelope` state.

```bash
lake exe zil -- summary graph.zilx
lake exe zil -- closure graph.zilx
lake exe zil -- check graph.zilx $'rel\tnode:claim.a\tzil.supportedBy\tnode:source.paper'
lake exe zil -- query graph.zilx $'rel\tvar:claim\tzil.supportedBy\tvar:source'
lake exe zil -- export graph.zilx prolog
lake exe zil -- repl graph.zilx
lake exe zil -- apply-delta graph.zilx update.zild graph-next.zilx
```

The REPL supports `summary`, `closure`, `check`, `query`, `export souffle`, `export prolog`, and `quit`.

All commands use the same native `Zil.Term`, `RelExpr`, `Rule`, query engine, exchange protocol, delta protocol, and logic exporters as imported Lean modules. No Clojure subprocess is required.

Lean remains pinned to `leanprover/lean4:v4.31.0`.
