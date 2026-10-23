# Interop: HCL import and TLA+ / Lean export v1

`zilInterop` moves models between ZIL and other formats.

## `import-hcl <file-or-dir> [out|-] [module]`

Reads Terraform/OpenTofu text (`.tf` and `.hcl` files; below a directory, sorted by path) and writes ZIL: a `PROVIDER`
declaration per provider named in `required_providers` (source, version, `language=hcl`, `engine=opentofu`), then facts
per top-level block (`provider`, `resource`, `data`, `module`, `variable`, `output`): the block's file
(`hcl:file:<name with . as _>`), type and name, the provider it uses, and one `attr` fact per top-level scalar attribute
carrying its key and raw text. Nested objects and lists are skipped. Comments (`#`, `//`, `/* */`) and strings are respected
when counting braces. A number prints as `Double.toString` would (`5.0E-4`). The module name defaults to `hcl.import`.
A path with no `.tf` or `.hcl` file is refused.

## `export-tla <file-or-dir> [out|-] [module]` and `export-lean <file-or-dir> [out|-] [namespace]`

Both read `LTS_ATOM` declarations (`states`, `initial`, `transitions`; an atom may add effects and a canonical trace) from
`.zc` files, a directory being searched for `*.zc`. Each atom is an actor named from its id.

`export-tla` writes a TLA+ module `<MODULE>_LTSBridge` (the MODULE of a single-module input, else `ZilLTSBridge`, or the
`module` argument; characters outside letters, digits and `_` become `_`, and a leading digit gets an `M_` prefix) that
extends `Sequences, FiniteSets, TLC` and defines, per actor, its state set, initial state, transitions
`<< from, action, to >>`, transition effects and canonical trace, and the system's `CanonicalSystemTrace`.

`export-lean` writes a Lean file under the namespace `Zil.Generated.<Module words>` (or the `namespace` argument) with, per
actor, an inductive state type and an inductive event type (each with a comment mapping source names to constructors),
the initial state, a total step function (an event with no transition leaves the state unchanged), and the canonical trace.
Names are split into words and recased; Lean reserved words get a trailing underscore; a collision gets `_1`, `_2`.

Each file starts with a generator header. An input with no `MODULE`, no `LTS_ATOM`, or an unreadable path is refused
(exit 2).

## Differences from the earlier implementation

The exporters read the native typed `LTS_ATOM` declarations. Output is
byte-identical on the inputs the tests use, which include a module whose name starts with a digit and a directory input.
