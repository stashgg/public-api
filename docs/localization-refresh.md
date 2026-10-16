# Refreshing a shop's localizations

This guide describes one call: your backend tells Stash that your localization file has changed, and Stash refreshes the shop's localizations from it.

Call it whenever the localization file changes. Stash queues the refresh and answers straight away; the import itself runs afterwards.

## Base URLs

| Environment    | Base URL                    |
| -------------- | --------------------------- |
| **Test**       | `https://test-api.stash.gg` |
| **Production** | `https://api.stash.gg`      |

## Request

```
POST {base URL}/sdk/studio/{shop_id}/localizations/refresh
Content-Type: application/json
x-stash-hmac-signature: v1;{shop_id};{timestamp};{signature}

{}
```

- `{shop_id}` is your shop identifier from Stash Studio.
- The body is always the empty JSON object `{}`: two bytes, with no spaces or newline.
- Only the versioned `x-stash-hmac-signature` header is accepted. The older `stash-hmac-signature` header is refused with `401`, because it carries no timestamp and a captured request could be replayed.

## Signing the request

Sign every request with your **Ingress** API key. The Egress key, which Stash uses to call your game backend, does not work here.

1. In **Stash Studio > Project Settings > API Secrets**, copy your Ingress API key and store it securely, exactly as shown.
2. Studio shows the key Base64-encoded. Base64-decode it to raw bytes and use those bytes as the HMAC key. Signing with the encoded text produces a signature Stash rejects.
3. Take the current time as a Unix timestamp in **milliseconds**, for example `1790000000000`.
4. Build the string to sign as `{timestamp}.{body}`. The body is exactly what you send, `{}`, so the string is, for example, `1790000000000.{}`.
5. Compute HMAC-SHA256 of that string with the decoded key and Base64-encode the result.
6. Send `x-stash-hmac-signature: v1;{shop_id};{timestamp};{signature}`. The `{shop_id}` in the header must be the same as the one in the path, and the timestamp must be within 5 minutes of Stash server time.

Give every request, including every retry, its own timestamp and signature.

## Example (bash and python)

Keep the key, exactly as Studio shows it, in a file with owner-only permissions or in a secret store, and read and Base64-decode it inside the signing process. Never pass it as a command-line argument: process listings and shell history can capture it.

```bash
# sign <body>: prints the header value for the exact body you are about to
# send. Every request gets its own timestamp and signature.
sign() {
  local ts sig
  ts=$(($(date +%s) * 1000))
  sig=$(TS="$ts" BODY="$1" python3 - <<'PY'
import base64, hashlib, hmac, os
key = base64.b64decode(open(os.path.expanduser('~/.stash/ingress-key'), 'rb').read().strip())
msg = (os.environ['TS'] + '.' + os.environ['BODY']).encode()
print(base64.b64encode(hmac.new(key, msg, hashlib.sha256).digest()).decode())
PY
)
  printf 'v1;%s;%s;%s' '{shop_id}' "$ts" "$sig"
}

# Sign the exact bytes you send, then send them with --data-binary, which
# keeps them intact.
BODY='{}'
curl -X POST -H "Content-Type: application/json" \
  -H "x-stash-hmac-signature: $(sign "$BODY")" \
  --data-binary "$BODY" \
  "https://test-api.stash.gg/sdk/studio/{shop_id}/localizations/refresh"
```

## Response

A successful call answers `200` with:

```json
{ "accepted": true }
```

`accepted: true` means Stash has durably queued the refresh. It does not mean the import has finished, or that the storefront already shows the new text; that follows once the queued refresh runs.

## Errors and retries

| Status                      | Meaning                                                                                                                                                                                                         | What to do                                                                                                                                                                             |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `401`                       | The signature is missing or invalid, the timestamp is more than 5 minutes from Stash server time, the legacy header was used, or the header names a different shop from the path or a shop Stash does not know. | Fix the signing: decode the key, sign exactly `{}`, use a fresh millisecond timestamp, match the shop in header and path, and check the `{shop_id}`. Retrying unchanged will not help. |
| `400` (failed precondition) | The shop has no enabled localization source.                                                                                                                                                                    | Make sure the shop's localization source is set up and enabled; contact Stash if it should already be. Retrying will not help until it is.                                             |
| `503`                       | Stash could not queue the refresh.                                                                                                                                                                              | Retry with backoff.                                                                                                                                                                    |

Repeated calls are safe. If a call times out, returns `503`, or fails with another server error, send it again with a new timestamp and signature.
