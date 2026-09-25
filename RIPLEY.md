---
standard-version: 1.6.1
---

Review changes to this repository as changes to the public protobuf, JSON, OpenAPI, and generated-client contracts used by game backends and partners. Post a finding only when a specific request, response, currency, shop, or sequence would produce a wrong result, rejection, disclosure, or broken contract. Otherwise stay silent.

## What NOT to flag

Leave formatting, Buf lint and file-level breaking checks, and generated OpenAPI freshness to `.github/workflows/check.yml` and `Makefile`. Do not request style-only proto rewrites, blanket test coverage, or hand-edits to generated clients. Do not treat platform-dependent churn in `docs/gen/redoc.v1.html` or `docs/gen/redoc.ingress.v1.html` as a defect without a changed API behavior; CI intentionally excludes those HTML files from its freshness check.

## 1. loyalty-reward-parity (B1)

Keep the numeric values and meanings of `LoyaltyRewardType` aligned in `server/egress/shop/v1/enums.proto` and `server/ingress/loyalty/v1/enums.proto`. A new reward kind must use the same value on the purchase snapshot and partner loyalty read sides; a protobuf compiler cannot detect semantic disagreement between these separate enums.

**Failure:** A reward kind is decoded as a different kind across the egress and ingress loyalty contracts.

## 2. egress-https-contract (B3)

Keep the published transport schemes in `docs/config/swagger-merger-config.json` consistent with the HTTPS scheme in `server/egress/server.proto`. The merger config currently includes HTTP, so treat a change that carries that disagreement into a changed API description as a contract defect rather than assuming regeneration corrects it.

**Failure:** Generated shop API documentation directs a game backend to send signed requests over HTTP.

## 3. ingress-signature-docs (B3)

Reconcile the hand-written authentication instructions in `docs/config/swagger-merger-ingress-config.json` with `server/ingress/server.proto` when either contract changes. The proto recommends versioned `x-stash-hmac-signature` and marks `stash-hmac-signature` legacy, while the merger description currently presents only the legacy header; regeneration preserves that contradiction.

**Failure:** A partner follows published ingress instructions and sends signatures without the versioned format's replay window.

## 4. free-claim-identity (B4)

Preserve the `GetCatalogResponse.CatalogItem.FreeItem.claim_id` contract in `server/egress/shop/catalog/v1/service.proto`: the same claim ID denotes one claim in a period, only one item per claim ID should appear in a response, and a locked preview needs a distinct claim ID or none. Check changes to this field against the free-item consumer behavior described there.

**Failure:** Claiming one free item consumes or suppresses a different reward that shares its claim identity.

## 5. loyalty-payload-presence (B4)

Keep `loyalty` absent from `RegisterPaymentRequest` and `ConfirmPaymentRequest` in `server/egress/shop/purchase/v1/service.proto` for shops without an active loyalty campaign. Both fields are explicitly additive and optional so the game backend receives its previous request shape for those shops.

**Failure:** A non-loyalty shop's game backend receives an unexpected loyalty payload on a purchase request.

## 6. purchase-confirm-error-status (B4)

Keep `PurchaseService.ConfirmPayment` in `server/egress/shop/purchase/v1/service.proto` on its documented HTTP error-status path for failed confirmations. A change to its operation description or response contract must preserve how the caller distinguishes failed delivery from completed delivery.

**Failure:** A failed confirmation is treated as delivered because its error is hidden in an HTTP success response.

## 7. purchase-inline-status (B4)

Keep `PurchaseService.RegisterPayment` and `CancelPayment` in `server/egress/shop/purchase/v1/service.proto` on their documented HTTP 200 response path with success or failure expressed by `RegisterPaymentResponse.OfferStatus.status` and `CancelPaymentResponse.status`. A changed contract must leave the game backend's status decision visible in the body.

**Failure:** A failed registration or cancellation is treated as successful because its HTTP 200 response is read without its inline status.

## 8. sku-product-identity (B4)

Keep `ManagedCatalogService.GetProduct` and `Product.product_id` in `server/ingress/studio/v1/service.proto` keyed by the partner's SKU within a shop. The former `guid` slots are reserved in `GetProductRequest` and `Product`; do not describe internal GUIDs as the lookup key.

**Failure:** A partner's valid SKU lookup misses its product or resolves a different product identity.

## 9. zero-decimal-regression (B5)

When changing purchase request serialization or `optional decimal_places` in `server/egress/shop/purchase/v1/service.proto`, pin a regression check that emits a zero-decimal request with `decimalPlaces: 0`. `make check` in `Makefile` cannot prove that emitted JSON retains the literal zero.

**Failure:** A later schema or generator change again omits `decimalPlaces: 0` and valid zero-decimal purchases are rejected.

## 10. shop-player-scope (C1)

Keep player-specific loyalty reads scoped by both shop and player in `LoyaltyService.GetPlayerLoyalty` and `GetPlayerLoyaltyRequest` in `server/ingress/loyalty/v1/service.proto`. Do not recast `player_id` alone as sufficient to select a loyalty standing.

**Failure:** A request for one shop exposes another shop's player's loyalty balance or tier.

## 11. hmac-body-integrity (C3)

Keep the versioned HMAC descriptions in `server/ingress/server.proto` and `server/egress/server.proto` bound to the exact request body, including the documented empty body for ingress GET requests. A changed signing format must not make the signature independent of the payload it authenticates.

**Failure:** A request body is altered after signing and still appears authenticated.

## 12. hmac-replay-window (C3)

Keep the signed timestamp and five-minute acceptance window in the versioned HMAC descriptions in `server/ingress/server.proto` and `server/egress/server.proto`. A changed signing format must still let receivers reject a captured old request.

**Failure:** A stale signed request is replayed and accepted outside its intended time window.

## 13. ingress-egress-key-scope (C3)

Keep the Ingress key for partner-backend-to-Stash calls and the Egress key for Stash-to-game-backend calls, as defined separately in `server/ingress/server.proto` and `server/egress/server.proto`. Do not present either key as interchangeable in API descriptions or signing examples.

**Failure:** A key issued for one API direction is reused to authenticate the other direction.

## 14. signing-secret-exposure (C3)

Do not place a real signing key in command arguments, URLs, or logged output in examples for `docs/config/swagger-merger-ingress-config.json`. Its current `openssl dgst -hmac "YOUR_API_SECRET"` example becomes an argv exposure if a partner substitutes a real key; changes to signing guidance must avoid that pattern.

**Failure:** A partner's Ingress key becomes visible through a process list or captured command log.

## 15. minor-unit-scale (D1)

Preserve integer CLDR minor-unit meaning for `PriceAmountOrId.PriceAmount.cents` in `server/egress/shop/catalog/v1/service.proto`, purchase `cents`, `tax`, and `total` in `server/egress/shop/purchase/v1/service.proto`, and `Price.cents` in `server/ingress/studio/v1/service.proto`. Keep the ISO currency and applicable CLDR fraction digits tied to the same amount; do not recast these wire values as floating major units.

**Failure:** A game backend or partner charges or displays an amount different from the intended exact minor-unit price.

## 16. zero-decimal-presence (D1)

Keep `decimal_places` present even when its value is zero in `RegisterPaymentRequest`, `CancelPaymentRequest`, and `ConfirmPaymentRequest` in `server/egress/shop/purchase/v1/service.proto`. Their `optional uint32` fields and required OpenAPI descriptions encode the zero-decimal currency case; a plain proto3 scalar or JSON omission loses it.

**Failure:** A game backend rejects a valid JPY or KRW purchase because `decimalPlaces: 0` disappeared from the request.
