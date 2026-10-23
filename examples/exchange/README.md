# Exchange examples

`parse-request.json` demonstrates the canonical `ZIL-EXCHANGE/1` request field order.

Its `input_sha256` is a placeholder so the file remains readable. The worker validates the digest identifier and carries it through the response; the caller computes SHA-256 over the exact input bytes. To exercise the worker with the placeholder:

```bash
bin/zil worker --once < examples/exchange/parse-request.json
```

For a request with a real digest, compute `sha256:` plus the SHA-256 of `examples/authorization/access.zc` and put it in the `input_sha256` field before running the same command.
