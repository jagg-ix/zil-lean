# Macro extension parity example

This directory demonstrates the same macro-library workflow supported by the original Clojure implementation.

The model is:

```text
examples/macro-extension/model.zc
```

Its nearest ancestor contains:

```text
examples/macro-extension/lib/10-grants.zc
examples/macro-extension/lib/20-service-extension.zc
```

Library files are loaded non-recursively in filename order before the model.

## Expand

```bash
bin/zil macro-expand \
  examples/macro-extension/model.zc \
  --output /tmp/macro-extension.expanded.zc
```

The expansion contains:

- a `SERVICE` declaration;
- an owner fact emitted through nested `USE`;
- a rule deriving viewers from owners;
- a query selecting viewers.

## Compile

```bash
bin/zil macro-compile \
  examples/macro-extension/model.zc \
  --output /tmp/MacroExtension.lean \
  --namespace Zil.Generated.MacroExtension
```

## Compare frontends

```bash
bin/zil macro-parity \
  examples/macro-extension/model.zc \
  --output /tmp/macro-parity.edn
```

The parity command composes the source once, expands it with both the Clojure and native Lean frontends, and requires the ordered expanded statement vectors to be identical.

Use `--lib DIR` to replace nearest-ancestor discovery with an explicit macro library directory.
