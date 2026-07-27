# Embedded native examples

This directory contains ZIL annotations attached to Lean and Python declarations plus a Markdown block with an explicit target.

Compile every block through the native frontend:

```bash
clojure -M:embedded-native \
  --root examples/embedded-native \
  --out generated/embedded \
  --manifest generated/embedded/manifest.edn \
  --require-blocks
```

The generated modules are placed below:

```text
generated/embedded/EmbeddedNative/
```

Each manifest entry retains its host path, language, line span, resolved target, source hashes, generated namespace, and output hash.
