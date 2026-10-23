# Macro extension example

This directory demonstrates the macro-library workflow: a model that uses macros, and a `lib/` directory whose files are composed before it.

The model is:

```text
examples/macro-extension/model.zc
```

Its library is:

```text
examples/macro-extension/lib/10-grants.zc
examples/macro-extension/lib/20-service-extension.zc
```

Library files are loaded non-recursively in filename order before the model.

## Expand

```bash
bin/zil expand examples/macro-extension/model.zc /tmp/macro-extension.expanded.zc \
  --lib examples/macro-extension/lib
```

The expansion contains:

- a `SERVICE` declaration;
- an owner fact emitted through nested `USE`;
- a rule deriving viewers from owners;
- a query selecting viewers.

## Compile

```bash
bin/zil compile examples/macro-extension/model.zc /tmp/MacroExtension.lean \
  Zil.Generated.MacroExtension --lib examples/macro-extension/lib
```

## Qualify

`tools/macro_extension_matrix.sh` expands this and every other macro library natively, compares each expansion with its reviewed golden under `spec/macro-extension-golden/`, compiles it, and typechecks the generated Lean.
