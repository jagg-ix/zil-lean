# Datasource ingest v1

`DATASOURCE` declarations name where records come from. `zilIngest run` reads them, turns records into facts and causal
edges, and writes the result as JSON, as ZIL source and as a revision log (`ZILR/1`, the format `bin/zil snapshot` and
`causal-check` read). The same module converts data files between formats and imports them as facts.

## Declaration

```text
DATASOURCE name [type=file|command|rest|cucumber, ...].
```

`type` is required; `socket`, `websocket` and `pipe` are declared but have no adapter and are refused. `format` is one of
`json text csv edn kv yaml yml`; `poll_mode` is `event` (default) or `interval`. The datasource id is `datasource:<name>`
(the name itself when it contains `:`). String values read `\"`, `\\`, `\n`, `\t`, `\r` as escapes.

| Adapter | Attributes | Records |
|---|---|---|
| `file` | `path` (or `file`); `mode` or `format`, default `lines` | `lines`: `{line_number, line}` per line; `text`: `{text}`; a format: the decoded payload |
| `command` | `command` (run with `bash -lc`), `format`, `timeout_ms` (60000) | no `format`: `{exit, stdout, stderr}`; with it, the decoded stdout, each record gaining `command_exit` and, if stderr is not blank, `command_stderr` |
| `rest` | `mock_responses` or `mock_response` (JSON, or EDN), else `url`, else `path`; `format` (json for a `url`, else text); `method`, `headers`, `body`, `timeout_ms` (5000) | the decoded payload; `text` gives `{raw}` |
| `cucumber` | `path` to a Cucumber JSON report | one record per step of every `scenario` or `scenario_outline`, with `event_id`, a one-component `vector_clock`, and `before` the previous step |

HTTP uses `curl`; a status of 400 or more, or no answer, is an error.

## Formats

JSON and EDN as usual (an EDN keyword is read as its name). `text` is the whole text. `csv` has a header row unless
`csv_header=false`, delimiter `csv-delimiter` (`,`), typed cells unless `csv_typed=false`; header cells are lower-cased,
other characters become `_`, an empty one is `col_N`. `kv` is `key=value` lines (`#` comments, keys lower-cased, typed
unless `kv_typed=false`). `yaml` is the small subset the earlier tools had: JSON if the text starts with `{` or `[`,
else a list of `- key: value` items or a flat `key: value` document; text after whitespace and `#` is a comment; keys are
lower-cased. Typed cells: `true`/`false`, integers (in the 64-bit range), decimals, a double-quoted string read as an EDN
string, else the text. Objects keep the order they were written in; a repeated key keeps the first position and the last
value.

## Records to facts

A record that is not an object becomes `{value: record}`. With `ts` the ingest time in milliseconds, a record gives, in order:

1. `<datasource> ingested_record value:record [ingest_ts, payload=record]`;
2. a metric observation, `metric:<m> observed_from <datasource> [value, ingest_ts]`, when `metric` is set (not null or false)
   and `value` is present, else one per entry of a `metrics` object;
3. when the record has an event id and a `vector_clock` object, `<event> vc_component actor:<actor> [counter, ingest_ts]` per
   actor (counters: integers, numbers truncated, numeric text; anything else is refused);
4. `<datasource> <key> <subject> [ingest_ts]` for every other key (not `metric value metrics before vector_clock event_id
   event-id`), where a text subject is itself if it contains `:` or starts with `?`, else `value:<text>`; numbers, booleans and
   `nil` are `value:<printed>`; arrays and objects are `value:` and their EDN print.

The event id is the first of `event_id`, `event-id`, `event` that is not blank, with `event:` before it unless it contains
`:`, and every character outside `A-Za-z0-9_:-.` made `_`. Every fact of the record carries that event, or
`ingest_<datasource id with : as _>`; all carry the run's revision.

## Causal edges

An event with `before: [...]` gets an edge from each listed event. Events with vector clocks get an edge `a → b` when `a ≠ b`
and `a`'s clock is no greater anywhere and smaller somewhere. The edges of a source are the distinct union. The counts
`before_edges`, `before_edges_explicit` (before duplicates are removed) and `before_edges_derived` are reported per source.

## Run

`zilIngest run <model.zc>` reads every datasource once, or an `interval` source `--polls` times, sleeping `poll_every_ms`
between runs. Revision: `--revision N` for all, else the timestamp for an event source and `--initial-revision + k` (default
the timestamp) for poll *k* of an interval source. Outputs: `--json` (`ZIL-INGEST/1`: counts, `by_source`, `fact_list`,
`before_edge_list`), `--zc` (ZIL source; a term that would not parse is double-quoted, attribute values that are not
scalars are JSON text), `--zilr`.

A store keeps one fact per (object, relation, subject): a later fact at the same revision replaces an earlier one. The
revision log is built that way, and edges that name an event with no fact are left out and counted on standard error.

## Data files

`import-data <file> [out] [module] [format] [prefix]` writes `<prefix>:<n> kind entity:interop_record` and one fact per key
per record (`<prefix>:<n>#<key>@<subject>.`, keys lower-cased with other characters `_`). `convert <file> <format>` reads a
file (format from its extension or `--from`) and writes the payload in another format.

## Differences from the earlier implementation

The facts go to JSON, ZIL source and a revision log instead of an in-process database. HTTP is done by `curl`. EDN keywords
are read as names. A term that would not parse as ZIL source is quoted. A map with more than eight keys keeps the order it
was written in. `export-data` (the model's query results as JSON, YAML or CSV) is not provided: it needed the second
evaluator and its spellings of names.
