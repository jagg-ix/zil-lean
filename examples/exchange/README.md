# Exchange examples

`parse-request.json` demonstrates the canonical `ZIL-EXCHANGE/1` request field order.

Its `input_sha256` is a placeholder so the file remains readable. For an executable request, use the Clojure control-plane command, which computes SHA-256 over the exact current input bytes:

```bash
bin/zil exchange parse examples/authorization/access.zc
```

To exercise the Lean worker directly, replace the placeholder digest with the exact SHA-256 of `examples/authorization/access.zc`, then run:

```bash
bin/zil worker --once < examples/exchange/parse-request.json
```

The direct worker validates the digest identifier and carries it through the response. Version 1 assigns actual file-byte attestation to the Clojure client.
