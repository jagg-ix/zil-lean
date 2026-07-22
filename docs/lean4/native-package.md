# Native Lean package

The repository's established Lean version is `v4.31.0`. The root `lean-toolchain` pins exactly that version.

## Build

```bash
lake build
```

## Run the core IR validation executable

```bash
lake exe zilLeanTests
```

## Package boundary

The native package currently defines only the shared semantic data structures:

- `Zil.Term`
- `Zil.RelExpr`
- `Zil.Rule`
- `Zil.Query`
- `Zil.TrustClass`

It does not yet introduce custom syntax, environment extensions, theorem attributes, or external runtime calls. Those are separate PR targets.

The package deliberately depends only on Lean's bundled libraries. It does not query Clojure, DataScript, SQLite, GitHub, or a network service during elaboration.
