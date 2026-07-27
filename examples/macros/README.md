# Macro example

Inspect the expanded source:

```bash
lake exe zil -- expand examples/macros/access.zc
```

Compile it to native Lean:

```bash
lake exe zil -- compile \
  examples/macros/access.zc \
  /tmp/MacroAccess.lean \
  Example.MacroAccess
```

The example expands `grantPlatform` into `grant`, then into a userset tuple. The
native userset rule derives that `user:11` can view `doc:readme`.
