# Pulling a shop's transaction records

This guide describes one call: your backend pulls the rows of a shop's Financial Report for a time window. The Financial Report is the settled-transaction report that you already reconcile payouts against. Each record the API returns is one row of that report, with the same meaning, signs and settlement dating, so the totals of the records equal the report and the payout.

Call it on a schedule, for example once a day. Start each pull at the `availableUntil` of your last complete pull. Re-pull every window that overlaps a month whose final report does not exist yet, even when the window returned no records (see [Finality and re-pulls](#finality-and-re-pulls)).

## Base URLs

| Environment    | Base URL                    |
| -------------- | --------------------------- |
| **Test**       | `https://test-api.stash.gg` |
| **Production** | `https://api.stash.gg`      |

## Request

```
GET {base URL}/sdk/studio/{shop_id}/transactions?startAt={startAt}&endAt={endAt}
x-stash-hmac-signature: v1;{shop_id};{timestamp};{signature}
```

- `{shop_id}` is your shop identifier from Stash Studio.
- The request has no body. You sign the empty string.
- Only the versioned `x-stash-hmac-signature` header is accepted. The older `stash-hmac-signature` header is refused with `401`, because it carries no timestamp and a captured request could be replayed.

| Query parameter | Required | Meaning                                                                                                                                                  |
| --------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `startAt`       | yes      | The start of the window, inclusive, as an RFC 3339 timestamp, for example `2026-10-01T00:00:00Z`. Stash compares it with the `ts` of each record.        |
| `endAt`         | yes      | The end of the window, exclusive, as an RFC 3339 timestamp. It must be later than `startAt` and at most 31 days after it. See [Window](#window).        |
| `limit`         | no       | The maximum number of records per page, from 1 to 100. The default is 50.                                                                              |
| `pageToken`     | no       | The `nextPageToken` of the previous response. Leave it out on the first page. The token is opaque: do not parse it or build it yourself. See [Paging](#paging). |

## Signing the request

Sign every request with your **Ingress** API key. The Egress key, which Stash uses to call your game backend, does not work here.

1. In **Stash Studio > Project Settings > API Secrets**, copy your Ingress API key and store it securely, exactly as shown.
2. Studio shows the key Base64-encoded. Base64-decode it to raw bytes and use those bytes as the HMAC key. Signing with the encoded text produces a signature Stash rejects.
3. Take the current time as a Unix timestamp in **milliseconds**, for example `1790000000000`.
4. Build the string to sign as `{timestamp}.{body}`. The request has no body, so the string ends with the dot, for example `1790000000000.`.
5. Compute HMAC-SHA256 of that string with the decoded key and Base64-encode the result.
6. Send `x-stash-hmac-signature: v1;{shop_id};{timestamp};{signature}`. The `{shop_id}` in the header must be the same as the one in the path, and the timestamp must be within 5 minutes of Stash server time.

Give every request, including every retry and every page, its own timestamp and signature.

## Example (bash and python)

Keep the key, exactly as Studio shows it, in a file with owner-only permissions or in a secret store, and read and Base64-decode it inside the signing process. Never pass it as a command-line argument: process listings and shell history can capture it.

The example reads every page of one window. Replace the `echo` line with your own upsert by `recordId`. When it ends, it prints the `availableUntil` to start your next pull from.

```bash
set -euo pipefail

SHOP_ID='{shop_id}'
START_AT='2026-10-01T00:00:00Z'
END_AT='2026-11-01T00:00:00Z'
BASE_URL='https://test-api.stash.gg'

# sign: prints the header value for an empty body. Every request gets its own
# timestamp and signature.
sign() {
  local ts sig
  ts=$(($(date +%s) * 1000))
  sig=$(TS="$ts" python3 - <<'PY'
import base64, hashlib, hmac, os
key = base64.b64decode(open(os.path.expanduser('~/.stash/ingress-key'), 'rb').read().strip())
msg = (os.environ['TS'] + '.').encode()
print(base64.b64encode(hmac.new(key, msg, hashlib.sha256).digest()).decode())
PY
)
  printf 'v1;%s;%s;%s' "$SHOP_ID" "$ts" "$sig"
}

page_token=''
while :; do
  args=(--data-urlencode "startAt=$START_AT" --data-urlencode "endAt=$END_AT" --data-urlencode 'limit=100')
  if [ -n "$page_token" ]; then
    args+=(--data-urlencode "pageToken=$page_token")
  fi

  # -G sends the --data-urlencode values in the query string of a GET.
  response=$(curl -fsS -G \
    -H "x-stash-hmac-signature: $(sign)" \
    "${args[@]}" \
    "$BASE_URL/sdk/studio/$SHOP_ID/transactions")

  echo "$response"

  # The last page has no nextPageToken.
  page_token=$(printf '%s' "$response" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("nextPageToken", ""))')
  if [ -z "$page_token" ]; then
    break
  fi
done

# Start your next pull from this value. It is earlier than END_AT when the
# report data does not reach END_AT yet.
printf '%s' "$response" | python3 -c 'import json, sys; print(json.load(sys.stdin)["availableUntil"])'
```

## Response

A successful call answers `200` with one page:

```jsonc
{
  "records": [
    // Transaction records, see "Records and the Financial Report" and "Worked example".
  ],
  "nextPageToken": "...", // Present only when more records exist in the covered window.
  "asOf": "2026-10-21T02:15:00Z",
  "availableUntil": "2026-10-21T00:00:00Z"
}
```

A window with no records answers `200` with an empty `records` list. This is not an error.

## Window

The window is half-open: `[startAt, endAt)`. A record is in the window when its `ts` is at or after `startAt` and before `endAt`. The window is at most 31 days long, so a calendar month always fits.

`availableUntil` is the end of the report data available now. The response covers `[startAt, min(endAt, availableUntil))`. Stash does not refuse an `endAt` later than `availableUntil`, because you cannot know `availableUntil` before the first call. `availableUntil` is not a completeness bound. A later report can still add records before it, because records are dated by settlement and payment providers report settlements late. The re-pull rule in [Finality and re-pulls](#finality-and-re-pulls) brings you those records. When `availableUntil` is earlier than `endAt`, pull again later, with `availableUntil` as the new `startAt`.

## Records and the Financial Report

Each record is one row of the Financial Report. Field names in the JSON are lowerCamelCase. Timestamps are RFC 3339. Amounts, rates and percentages are strings.

| Field                         | Report column              | Meaning                                                                                                                                                              |
| ----------------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `recordId`                    | row identifier             | Identifies the report row, unique within the shop and stable across regenerations. Upsert your copy of each row by it.                                               |
| `transactionId`               | transaction ID (see below) | The transaction ID of the sale, the same value Stash sends in ConfirmPayment. Your join key to your own purchase records. All rows of one sale share it. |
| `type`                        | `type`                     | The kind of row. See [Row types and dispute statuses](#row-types-and-dispute-statuses).                                                                              |
| `orderId`                     | `order_id`                 | The checkout order the charge belongs to. For matching the report CSV; join by `transactionId` instead. Absent when the row has none.                                |
| `ts`                          | `ts`                       | The settlement time. For a failed payment, and for rows from before Stash's settlement-dating cutover, it is the charge time. The window filters on it.            |
| `chargedAt`                   | `ts__charged`              | When the player was charged.                                                                                                                                         |
| `settledAt`                   | `ts__settled`              | When the row settled. Absent when the row has not settled, for example a failed payment.                                                                             |
| `period`                      | `period__year`, `period__month` | The month of `ts` as `YYYY-MM`. It is the month of the report that carries the row.                                                                           |
| `final`                       |                            | `true` when the final report for `period` exists. See [Finality and re-pulls](#finality-and-re-pulls).                                                                |
| `taxCountry`                  | `tax_country`              | The country used for the tax calculation, as an ISO 3166-1 alpha-2 code. Absent when the row has none.                                                               |
| `taxState`                    | `tax_state`                | The state used for the tax calculation. Absent when the row has none.                                                                                                |
| `taxRatePercent`              | `tax_rate_percent`         | The tax rate applied, in percent, for example `"19.0000"`. Absent when the row has no rated tax line.                                                                |
| `charge.id`                   | `charge__id`               | Identifies the charge. Every row of one charge (its payment, refunds, disputes and adjustments) shares it.                                                           |
| `charge.status`               | `charge__status`           | The status of the charge for this row. See [Row types and dispute statuses](#row-types-and-dispute-statuses).                                                        |
| `charge.currency`             | `charge__currency`         | The ISO 4217 currency the player paid in, for example `EUR`.                                                                                                         |
| `charge.amount`               | `charge__amount`           | What the player paid, tax included, in the charge currency, signed as in the report.                                                                                 |
| `charge.taxAmount`            | `charge__tax_amount`       | The tax, in the charge currency.                                                                                                                                     |
| `charge.billingCountry`       | `charge__billing_country`  | Stash's best-known player location, as an ISO 3166-1 alpha-2 code. It is not a verified billing address. Absent when not known.                                      |
| `merchant.currency`           | `merchant__currency`       | The payout currency, as an ISO 4217 code.                                                                                                                            |
| `merchant.exchangeRate`       | `merchant__exchange_rate`  | The units of the payout currency per one unit of the charge currency that Stash applied.                                                                             |
| `merchant.amount`             | `merchant__amount`         | The gross settled amount. Negative on a refund and on a dispute withdrawal; zero on a failed payment.                                                                |
| `merchant.channelFees`        | `merchant__channel_fees`   | The payment processor's fee. Positive when charged on the row, negative when credited back. Usually not credited back on a refund. Zero by design under bundled pricing. |
| `merchant.tax`                | `merchant__tax`            | The tax withheld. Positive when charged on the row, negative when credited back (most refunds).                                                                      |
| `merchant.stashFee`           | `merchant__stash_fee`      | The Stash fee. Positive when charged on the row, negative when credited back (most refunds).                                                                         |
| `merchant.stashFeeWaived`     | `merchant__stash_fee_waived` | The part of the Stash fee that Stash waived. Usually zero or positive; negative when a refund reverses a waiver.                                                     |
| `merchant.payout`             | `merchant__payout`         | What Stash owes the shop for this row: `amount - channelFees - tax - stashFee + stashFeeWaived`. Can be negative.                                                    |
| `shopName` | `shop_name` | The shop's display name. Absent when your shop's report does not carry the column or the row has no value. |
| `purchaseTaxCalculationId` | `purchase_tax_calculation_id` | Identifies the tax calculation behind the row's tax. Quote it when you report a suspected tax error. Absent when your shop's report does not carry the column or the row has no value. |
| `creatorCodeId` | `creator_code_id` | The creator code attributed to the purchase. Absent when your shop's report does not carry the column or the row has no value. |
| `creatorCode` | `creator_code` | The code as the player entered it. Absent when your shop's report does not carry the column or the row has no value. |
| `creatorCodeName` | `creator_code_name` | The creator's display name at purchase time. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.failureMessage` | `charge__failure_message` | The payment provider's failure text. Set on failed payments. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.failureReason` | `charge__failure_reason` | Stash's normalized decline reason, for example `insufficient_funds` or `card_expired`. The set is open. Set on failed payments. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.description` | `charge__description` | The purchase description. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.cart` | `charge__cart` | The cart summary at checkout. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.cartId` | `charge__cart_id` | The cart the charge paid for. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.paymentMethod` | `charge__payment_method` | The payment method family, for example `card`, `paypal`, `apple_pay` or `google_pay`. The set is open. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.paymentSource` | `charge__payment_source` | How the purchase started, for example `Cart` or `StashPay`. The set is open. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.billingState` | `charge__billing_state` | The state or region of the billing address. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.cardCountry` | `charge__card__country` | The country of the card issuer, as an ISO 3166-1 alpha-2 code in uppercase. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.cardBrand` | `charge__card__brand` | The card brand, for example `visa`. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.cardFunding` | `charge__card__funding` | The card funding type: `credit`, `debit`, `prepaid` or `unknown`. The set is open. Absent when your shop's report does not carry the column or the row has no value. |
| `charge.cardNetwork` | `charge__card__network` | The card network. Absent when your shop's report does not carry the column or the row has no value. |

The `charge` and `merchant` objects and the `period`, `final`, `recordId`, `transactionId`, `type` and `ts` fields are always present. The fields that the table marks as absent in some cases are left out of the JSON when they have no value.

Stash configures report columns per shop. The descriptive fields appear only when your shop's report carries the column. Personal data such as the player ID or postal code is not in this API.

## Identifiers

`transactionId` joins records to your own purchase records. `recordId` identifies one row, and it is what you upsert. One sale has several rows (payment, refunds, disputes, adjustments) that share one `transactionId` and have different `recordId` values.

One `transactionId` can have several `payment` records: failed attempts before a successful one, and rarely a second successful payment. A purchase that Stash granted can have no successful `payment` record when the capture failed after the grant. Sum the `merchant` amounts of every record; do not assume one successful payment per transaction.

## Amounts and signs

Every amount is a signed decimal string in major units, for example `"-3.87"`. **Parse amounts as decimals, never as floating-point numbers.** A floating-point sum drifts from the exact total. Do not rely on a fixed number of decimal places.

In `merchant`, this identity holds exactly on every row, whatever its `type` or `charge.status`:

```
payout = amount - channelFees - tax - stashFee + stashFeeWaived
```

The sign of a deduction does not depend on the row type. It depends on what the row does with that column. Each column is zero when nothing happened on it.

| Column           | Positive                                                                          | Negative                                                                 | Notes                                                                                                                                                                                                 |
| ---------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `amount`         | A successful payment, a dispute's fund return                                     | A refund, a dispute withdrawal, a lost dispute that moves money again    | Zero on a failed payment.                                                                                                                                                                             |
| `channelFees`    | The row charges the processor's fee, for example an open dispute (chargeback fee) | A prior fee is credited back. This is rare, for example on a won dispute | Usually stays positive or zero on a refund, because the processor does not refund its own fee. On a failed payment it can be positive.                                                                |
| `tax`            | The row withholds tax                                                             | A prior tax is credited back, on most refunds                            | Zero on a failed payment.                                                                                                                                                                             |
| `stashFee`       | The row charges the Stash fee                                                     | A prior Stash fee is credited back, on most refunds                      | Zero on a failed payment.                                                                                                                                                                             |
| `stashFeeWaived` | Part of the Stash fee is waived                                                   | A refund reverses an earlier waiver                                      | Usually zero or positive.                                                                                                                                                                             |
| `payout`         | Stash owes the shop                                                               | The shop owes Stash                                                      | Usually follows the sign of `amount`. It can differ when the deductions are larger than the amount, for example on a very small payment. It is negative on a failed payment that has a processor fee. |

**Subtract the deductions exactly as stored.** Adding them, changing their signs, or filtering records by sign (for example keeping only records with a positive `payout`) gives a wrong payout. Do not use absolute values.

Add `merchant` amounts only within one `merchant.currency`. The `charge` amounts are in the charge currency and are not part of the identity. `charge.amount` is negative on a refund: its sign follows the direction of the money. `merchant.exchangeRate` is for reference: use the `merchant` amounts as Stash sends them and do not recompute them from the `charge` amounts.

## Finality and re-pulls

Every record has a `final` flag.

- **`final` is `true`** when the final report for the record's `period` exists. Stash generates the final report on day 5 of the next month (UTC). A final record never changes.
- **`final` is `false`** for a preliminary record. It can change, and it can disappear without a notice, for example when the report is regenerated.

To keep your copy equal to the report:

1. Upsert every record by `recordId`.
2. On every re-pull of a window, replace **all** preliminary records of that window in your copy with the records the response returns. A preliminary record that is no longer in the response is gone: delete it. Do this only after a complete walk whose pages all report the same `asOf`.
3. Re-pull a window until the final report exists for every month that the window overlaps, that is, after day 5 (UTC) of the month after the window's last month. Then pull it one last time. After that, you do not need to pull it again. Do not stop because the window returned no records or only final records: Stash can add records to a month until its final report exists.

Each page carries its own `asOf`: the time Stash built the snapshot of your shop's report data behind that page. One snapshot covers every month, final and preliminary, so a window that spans two months still has one `asOf`. Every page of one walk comes from the snapshot of its first page, because the `pageToken` carries it. If Stash rebuilds the report during your walk, the next page request returns `409`. Start the window again from the first page, without `pageToken`, and delete nothing because of that walk.

## Row types and dispute statuses

`type` and `charge.status` are strings. Both sets are open: Stash can add values. Store a record with a value you do not know, and do not reject it.

| `type`       | `charge.status` today                                                                       |
| ------------ | ------------------------------------------------------------------------------------------- |
| `payment`    | `succeeded` or `failed`                                                                     |
| `refund`     | `succeeded`                                                                                 |
| `dispute`    | `won`, `lost`, or any other value, such as `succeeded` or `needs_response`, which means the dispute is open |
| `adjustment` | `applied`                                                                                   |

Treat any dispute status other than `won` or `lost` as open. A `lost` row can carry money, and a second chargeback can add more, so never drop rows by status. Sum every row.

## Paging

The response carries `nextPageToken` while more records exist in the covered window. Send it as `pageToken` in the next call, with the same `startAt` and `endAt`, until a response has no `nextPageToken`. A token sent with a different window is refused. Sign every call again with a new timestamp.

Records are ordered by `ts`, then `recordId`. The token holds the window, the position and the snapshot of the walk's first page. If Stash rebuilds the report between two pages, the next call returns `409`: start the window again from the first page. See [Finality and re-pulls](#finality-and-re-pulls).

## Worked example

The numbers are illustrative. They satisfy the identity exactly. The example shows a payment and its full refund. The player paid 119.00 EUR, which includes 19.00 EUR tax, and the payout currency is USD at the rate 1.0850.

The payment charged a processor fee, tax and the Stash fee, and Stash waived part of the Stash fee. It settled on September 30, so it belongs to the period `2026-09`. The report for September exists, so `final` is `true`.

```json
{
  "recordId": "row_01",
  "transactionId": "3f0c7a52-8d1e-4b6a-9c3d-5e21a7b4f908",
  "shopName": "Example Shop",
  "type": "payment",
  "orderId": "order_01",
  "ts": "2026-09-30T10:12:08Z",
  "chargedAt": "2026-09-28T17:03:41Z",
  "settledAt": "2026-09-30T10:12:08Z",
  "period": "2026-09",
  "final": true,
  "taxCountry": "DE",
  "taxRatePercent": "19.0000",
  "charge": {
    "id": "charge_01",
    "status": "succeeded",
    "currency": "EUR",
    "amount": "119.00",
    "taxAmount": "19.00",
    "billingCountry": "DE",
    "paymentMethod": "card",
    "cardBrand": "visa"
  },
  "merchant": {
    "currency": "USD",
    "exchangeRate": "1.0850",
    "amount": "129.12",
    "channelFees": "3.87",
    "tax": "20.62",
    "stashFee": "6.46",
    "stashFeeWaived": "0.65",
    "payout": "98.82"
  }
}
```

Check: `129.12 - 3.87 - 20.62 - 6.46 + 0.65 = 98.82`.

The refund returned the full amount on October 16. It has its own `recordId`, the same `charge.id`, and it credits back the tax and the Stash fee and reverses the waiver. The processor does not return its fee, so `channelFees` is `0.00`. It belongs to the period `2026-10`. The report for October does not exist yet, so `final` is `false`. The refund carries the same `transactionId` as the payment.

```json
{
  "recordId": "row_02",
  "transactionId": "3f0c7a52-8d1e-4b6a-9c3d-5e21a7b4f908",
  "shopName": "Example Shop",
  "type": "refund",
  "orderId": "order_01",
  "ts": "2026-10-16T09:41:55Z",
  "chargedAt": "2026-09-28T17:03:41Z",
  "settledAt": "2026-10-16T09:41:55Z",
  "period": "2026-10",
  "final": false,
  "taxCountry": "DE",
  "taxRatePercent": "19.0000",
  "charge": {
    "id": "charge_01",
    "status": "succeeded",
    "currency": "EUR",
    "amount": "-119.00",
    "taxAmount": "-19.00",
    "billingCountry": "DE",
    "paymentMethod": "card",
    "cardBrand": "visa"
  },
  "merchant": {
    "currency": "USD",
    "exchangeRate": "1.0850",
    "amount": "-129.12",
    "channelFees": "0.00",
    "tax": "-20.62",
    "stashFee": "-6.46",
    "stashFeeWaived": "-0.65",
    "payout": "-102.69"
  }
}
```

Check: `-129.12 - 0.00 - (-20.62) - (-6.46) + (-0.65) = -102.69`.

Together the two rows net to `-3.87` USD: the processor kept its fee. Signs follow what each row charged or credited back, not the row type.

## Errors and retries

| Status | Meaning                                                                                                                                                                                                                                                                      | What to do                                                                                                                                                                                                |
| ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `401`  | The signature is missing or invalid, the timestamp is more than 5 minutes from Stash server time, the legacy header was used, or the header names a different shop from the path or a shop Stash does not know.                                                              | Fix the signing: decode the key, sign the empty body (`{timestamp}.`), use a fresh millisecond timestamp, match the shop in header and path, and check the `{shop_id}`. Retrying unchanged will not help. |
| `400`  | `startAt` or `endAt` is missing or malformed, `endAt` is not later than `startAt`, the window is longer than 31 days, `limit` is outside 1 to 100, `pageToken` is malformed, or `pageToken` was sent with a different window.                                                | Fix the request. Retrying unchanged will not help.                                                                                                                                                        |
| `409`  | Stash rebuilt the report after the `pageToken` was issued, so the walk cannot continue from one snapshot. | Start the window again from the first page, without `pageToken`. A retry with the same `pageToken` fails again. |
| `503`  | Stash could not read the data.                                                                                                                                                                                                                                               | Retry with backoff, with a new timestamp and signature.                                                                                                                                                   |

The call only reads data, so repeated calls are safe. If a call times out, returns `503`, or fails with another server error, send it again with a new timestamp and signature.
