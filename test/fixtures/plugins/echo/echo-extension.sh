#!/bin/sh
# An extension that is a separate command: one JSON request on standard input, one JSON answer on standard output.
request="$(cat)"
case "$request" in
  *'"op":"describe"'*)
    printf '%s\n' '{"capabilities":["echo-provider","evidence-producer"],"commands":{"echo":{"summary":"Return the arguments","arguments":["words"]},"fail":{"summary":"Exit with an error","arguments":[]}},"evidence":true}' ;;
  *'"op":"invoke"'*'"command":"fail"'*)
    echo "deliberate failure" >&2; exit 7 ;;
  *'"op":"invoke"'*)
    printf '%s\n' '{"echoed":true}' ;;
  *'"op":"evidence"'*)
    printf '%s\n' '[{"role":"echo","subject":"thing:one","payload":"hello","metadata":{"n":1}}]' ;;
  *) echo "unknown request" >&2; exit 9 ;;
esac
