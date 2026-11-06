---
standard-version: 1.6.1
---

Review changes to this repository as changes to the public protobuf, JSON, OpenAPI, and generated-client contracts used by game backends and partners. Post a finding only when a specific request, response, currency, shop, or sequence would produce a wrong result, rejection, disclosure, or broken contract, or when the change or its PR names a partner, game, or customer (`partner-name-disclosure`). Otherwise stay silent.

## What NOT to flag

Leave formatting, Buf lint and file-level breaking checks, and generated OpenAPI freshness to `.github/workflows/check.yml` and `Makefile`. Do not request style-only proto rewrites, blanket test coverage, or hand-edits to generated clients. Do not treat platform-dependent churn in `docs/gen/redoc.v1.html` or `docs/gen/redoc.ingress.v1.html` as a defect without a changed API behavior; CI intentionally excludes those HTML files from its freshness check. A new field, parameter, or enum value whose name and description leave open what it holds is not comment wording; `contract-field-naming` governs it. Values a diff adds to an enum or another value set are not a style preference; `wire-value-naming` governs them.

## 1. loyalty-reward-parity (B1)

Keep the numeric values and meanings of `LoyaltyRewardType` aligned in `server/egress/shop/v1/enums.proto` and `server/ingress/loyalty/v1/enums.proto`. A new reward kind must use the same value on the purchase snapshot and partner loyalty read sides; a protobuf compiler cannot detect semantic disagreement between these separate enums.

**Failure:** A reward kind is decoded as a different kind across the egress and ingress loyalty contracts.

## 2. egress-https-contract (B3)

Keep the published transport schemes in `docs/config/swagger-merger-config.json` consistent with the HTTPS scheme in `server/egress/server.proto`. Regeneration copies the merger config's `schemes` into the published reference as written, so treat a change that adds HTTP there, or otherwise lets the two disagree, as a contract defect rather than assuming regeneration corrects it.

**Failure:** Generated shop API documentation directs a game backend to send signed requests over HTTP.

## 3. ingress-signature-docs (B3)

Reconcile the hand-written authentication instructions in `docs/config/swagger-merger-ingress-config.json` with `server/ingress/server.proto` when either contract changes. Both present the versioned `x-stash-hmac-signature` header as the one to use and the legacy `stash-hmac-signature` header as deprecated and accepted only by the endpoints they list; regeneration preserves any contradiction a change introduces between them.

**Failure:** A partner follows published ingress instructions and sends signatures without the versioned format's replay window.

## 4. legacy-surface-removal-reach (B3)

When a diff removes, or stops serving, an operation, field, or signature header, update in the same change every place in this repository that still offers it: the hand-written descriptions in `docs/config/swagger-merger-config.json` and `docs/config/swagger-merger-ingress-config.json` (the ingress one lists the endpoints that still accept the legacy header), the security scheme descriptions in `server/ingress/server.proto` and `server/egress/server.proto`, and the endpoint sections of `README.md`.

**Failure:** A partner is told to integrate with a surface the contract no longer has, and the integration fails at runtime.

## 5. acknowledged-breaking-change (B4)

Keep every breaking change to these contracts visible to `buf breaking` and acknowledged where it is made. Do not add `ignore`, `ignore_only`, or `except` entries to the `breaking` section of `buf.yaml`, temporary or not; leave the check failing, and state in the PR description that the break is expected, which field or message breaks, and why that is safe for the game backends that consume it, for example that none sends or reads the field yet. The failing check is the deliberate marker that the break was made consciously; it does not block merging.

**Failure:** A breaking change reaches game backends unmarked, because a buf config exception silenced the check, or unexplained, because its PR never says why the break is safe for them.

## 6. contract-field-naming (B4)

When a diff adds a field, path parameter, or enum value to a contract under `server/`, check that its name, read with its enclosing message and its siblings, says what it holds, and that the text partners read says what it holds, which kind it is, and where it is displayed or consumed. Partners read a field's `openapiv2_field` `description` when it sets one and the comment above it otherwise, and the comment above an enum value; that text reaches the published reference in `docs/gen/` and every client `gen.sh` builds from it. Flag a new name that leaves this open and whose description does not settle it: a generic noun (`detail`, `data`, `info`, `value`, `type`, `id`, `name`, `url`); an image or URL field that does not say which image it is (an icon, a background, an illustration) or where it renders; text siblings (`text`, `label`, `message`) that do not say which line each one is; a number, duration, or size whose name and description carry no unit (`_millis`, `_bytes`); a boolean that does not read as a yes-or-no question (`is_`, `has_`); or a name that is vaguer than, or conflicts with, a sibling in the same message. Follow `GetCatalogResponse.Catalog.Section.EmptyState` in `server/egress/shop/catalog/v1/service.proto`, whose descriptions say that `image_url` is an illustration drawn between the section header and the message, that `message` is the line under it telling the player why the section has no offers, and that `call_to_action` is the line under that; `Section.subtitle` in the same file ("Optional short line shown under the section header"); and `ConfirmPaymentRequest.time_millis` in `server/egress/shop/purchase/v1/service.proto`, whose name carries its unit. A description that settles the meaning is as good a fix as a rename. Fields the diff does not add, and a name its enclosing message already qualifies or that follows an established sibling convention in the same message (`cents` beside `currency`), are out of scope. Post the finding as a question that leads with the concrete confusion and then offers a name or a description, as on a new message with `image_url`, `message` and `detail`: "which image is this: an icon, a background or an illustration, and where does it draw? could the field name or its description say so?" and "`detail` doesn't say what it holds next to `message`: a second line, a longer explanation or a caption? could it get a more descriptive name?"

**Failure:** A game backend or partner cannot tell from a new field, parameter, or value's name or description what it holds or where it is used, acts on a wrong guess, and the rename that would fix it later breaks every integration that already depends on the old name.

## 7. enum-zero-meaning (B4)

Give a new enum's `<ENUM>_UNSPECIFIED = 0` value a documented meaning, either the named default it behaves as or that it is rejected, as `CATALOG_SECTION_DISPLAY_TYPE_UNSPECIFIED` ("Default responsive grid layout") and `CATALOG_GROUP_DISPLAY_TYPE_UNSPECIFIED` ("Inherit section display behavior") in `server/egress/shop/catalog/v1/enums.proto` do.

**Failure:** A caller that leaves an enum field unset cannot tell whether the receiver applies a default or rejects the request.

## 8. error-status-contract (B4)

When a diff adds an operation or changes how one fails, its `openapiv2_operation` `description` names each error status the caller can receive, the condition behind each, and whether to retry, as `LocalizationService.RefreshLocalizations` in `server/ingress/localization/v1/service.proto` does: `UNAUTHENTICATED` for a missing, invalid, stale, legacy, or wrong-shop signature, `FAILED_PRECONDITION` when the shop has no enabled localization source, and `UNAVAILABLE`, after which the caller retries. A condition the caller must handle differently from success, such as a shop that is not set up for the feature or a request that can never be satisfied, gets its own status or a documented result; flag a contract that answers it with a success indistinguishable from an ordinary empty or not-yet-ready result. For an operation that reports failure inline in an HTTP 200 body, as `RegisterPayment` and `CancelPayment` do (`purchase-inline-status`), the same applies to each inline status value: its comment names the condition and whether to retry.

**Failure:** A caller cannot tell the real failure apart from success or from another failure, so it applies the wrong recovery, such as retrying forever on a condition that will never change.

## 9. external-consumer-contract (B4)

For a change to a field, enum, or operation that game backends or partners already use, state in the PR what an existing consumer sees before and after, including the changes `buf breaking` cannot see: a changed meaning, default, unit, or accepted range; a reworded guarantee in a description; or a new value in an enum a consumer receives. A new value in an enum the consumer receives says, in its comment or the enum's description, how a consumer that does not know the value yet should treat it. Trace the field to the side that acts on it rather than reviewing the proto edit in isolation: `server/egress` operations are called by Stash and implemented by the game backend, and `server/ingress` operations are implemented by Stash and called by partner backends.

**Failure:** A locally valid contract change silently breaks a game backend or partner whose existing integration was never checked against it.

## 10. free-claim-identity (B4)

Preserve the `GetCatalogResponse.CatalogItem.FreeItem.claim_id` contract in `server/egress/shop/catalog/v1/service.proto`: the same claim ID denotes one claim in a period, only one item per claim ID should appear in a response, and a locked preview needs a distinct claim ID or none. Check changes to this field against the free-item consumer behavior described there.

**Failure:** Claiming one free item consumes or suppresses a different reward that shares its claim identity.

## 11. legacy-surface-requirement (B4)

When a diff extends an operation, field, or header the contract marks deprecated or legacy, by adding fields, values, or behavior to it, such as the `legacyHmac` security scheme in `server/ingress/server.proto` and `server/egress/server.proto` or `GetPlayerResponse.Player.in_game_currency` in `server/egress/shop/user/v1/service.proto`, the PR states the recorded requirement for the new capability, without naming the partner (`partner-name-disclosure`). With no such requirement, ask whether the capability belongs on the surface that replaces it, such as the versioned `hmac` scheme or `wallet`. A fix that keeps existing integrations on the deprecated surface working, a change that touches it only incidentally (regenerated output, a moved file), and its removal are exempt. Recommend removing a deprecated surface only with evidence that its consumers have migrated; `legacy-surface-removal-reach` covers what a removal must reach.

**Failure:** New capability lands on a deprecated surface that no recorded requirement needs, so new integrations adopt the surface being retired instead of its replacement.

## 12. loyalty-payload-presence (B4)

Keep `loyalty` absent from `RegisterPaymentRequest` and `ConfirmPaymentRequest` in `server/egress/shop/purchase/v1/service.proto` for shops without an active loyalty campaign. Both fields are explicitly additive and optional so the game backend receives its previous request shape for those shops.

**Failure:** A non-loyalty shop's game backend receives an unexpected loyalty payload on a purchase request.

## 13. proto-closed-set-enum (B4)

Declare a new field whose valid values are a closed set the contract defines as an enum, not as a `string` whose allowed values live only in its description. Open-ended or externally defined values (ISO currency and country codes, locale tags, time zone names, IDs and SKUs the partner chooses) and existing in-use string fields, whose change `acknowledged-breaking-change` governs, are exempt.

**Failure:** A misspelled or differently cased value passes the contract and is silently treated as the default, or is caught only by validation that has drifted from the documented set.

## 14. proto-logical-requiredness (B4)

Mark a new field that must always be sent with `(google.api.field_behavior) = REQUIRED`, list it in its message's `json_schema` `required` array, and add matching `validate.rules` where an empty value is invalid, as `RefreshLocalizationsRequest.shop_id` in `server/ingress/localization/v1/service.proto` does. Do not mark a genuinely optional or defaultable field required, and keep the three in agreement when a field's requiredness changes.

**Failure:** A caller omits a mandatory value that the published reference shows as optional, and the receiver accepts an ambiguous zero value or rejects a request the reference said was valid.

## 15. proto-opaque-json-boundary (B4)

Use typed messages for data whose shape Stash or the game backend owns, not a `string` field carrying JSON or a `google.protobuf.Struct`. Raw JSON is acceptable only for a value one side intentionally passes through unread, and its description says so.

**Failure:** A contract hides inside an unchecked JSON string or an untyped `google.protobuf.Struct`, so its shape is missing from the published reference and generated clients, and either side can change it without any schema check noticing.

## 16. purchase-confirm-error-status (B4)

Keep `PurchaseService.ConfirmPayment` in `server/egress/shop/purchase/v1/service.proto` on its documented HTTP error-status path for failed confirmations. A change to its operation description or response contract must preserve how the caller distinguishes failed delivery from completed delivery.

**Failure:** A failed confirmation is treated as delivered because its error is hidden in an HTTP success response.

## 17. purchase-inline-status (B4)

Keep `PurchaseService.RegisterPayment` and `CancelPayment` in `server/egress/shop/purchase/v1/service.proto` on their documented HTTP 200 response path with success or failure expressed by `RegisterPaymentResponse.OfferStatus.status` and `CancelPaymentResponse.status`. A changed contract must leave the game backend's status decision visible in the body.

**Failure:** A failed registration or cancellation is treated as successful because its HTTP 200 response is read without its inline status.

## 18. sku-product-identity (B4)

Keep `ManagedCatalogService.GetProduct` and `Product.product_id` in `server/ingress/studio/v1/service.proto` keyed by the partner's SKU within a shop. The former `guid` slots are reserved in `GetProductRequest` and `Product`; do not describe internal GUIDs as the lookup key.

**Failure:** A partner's valid SKU lookup misses its product or resolves a different product identity.

## 19. wire-value-naming (B4)

When a diff adds an enum, or another set of two or more values that consumers compare against (status values, documented error reasons, type or format names), spell each subject one way across the set and its sibling sets: one stem for the same outcome and one noun for the same subject. Follow the enums in `server/egress/shop/purchase/v1/enums.proto`: `PurchaseRegistrationStatus` and `PurchaseCancellationStatus` share the `SUCCESS_` and `FAILED_` stems, and `PurchaseRegistrationStatus` and `PurchaseConfirmationStatus` give the same reason the same name after `FAILED_` (`INVALID_OFFER`, `INSUFFICIENT_INVENTORY`, `PURCHASE_LIMIT_EXCEEDED`). Flag a set that names one subject two ways where a consumer reading the names and their comments cannot tell whether the two values mean the same thing, such as `FAILED_INVALID_OFFER` in one enum beside `DECLINED_OFFER_NOT_VALID` in a sibling enum with no comment saying they are the same cause. Differently spelled values whose comments make the meaning unambiguous are not a finding. Buf lint already enforces the enum-name prefix and the `_UNSPECIFIED` zero value; values that name different subjects need no shared stem, and a value added to an existing set is checked against that set's spelling and against the same cause in its sibling sets.

**Failure:** A consumer cannot tell whether two differently spelled values name the same cause, and handles one of them as a different outcome.

## 20. zero-value-presence (B4)

When a diff adds a scalar field whose zero value carries its own meaning (a `false`, a `0`, or an empty string that differs from "not sent"), declare it `optional` so the JSON carries the zero, and say in its description that the zero is sent, as `ConfirmPaymentRequest.tax` in `server/egress/shop/purchase/v1/service.proto` does ("Always sent, including the literal 0 when the purchase has no tax"). Proto3 JSON omits a plain scalar's zero value unless its encoder is told to emit defaults. `zero-decimal-presence` governs the existing `decimal_places` fields.

**Failure:** A consumer receives no value where the contract meant `false`, `0`, or an empty string, and reads the field as unknown or applies its own default.

## 21. zero-decimal-regression (B5)

When changing purchase request serialization or `optional decimal_places` in `server/egress/shop/purchase/v1/service.proto`, pin a regression check that emits a zero-decimal request with `decimalPlaces: 0`. `make check` in `Makefile` cannot prove that emitted JSON retains the literal zero.

**Failure:** A later schema or generator change again omits `decimalPlaces: 0` and valid zero-decimal purchases are rejected.

## 22. cross-scope-isolation (C1)

A new ingress operation that reads or changes one shop's data takes the shop from the `{shop_id}` path parameter, and both its operation description and its `shop_id` field description state that the shop in the `x-stash-hmac-signature` header must equal it, as `LocalizationService.RefreshLocalizations` and `RefreshLocalizationsRequest.shop_id` in `server/ingress/localization/v1/service.proto` do. Do not accept the shop, or a second shop identifier, from the request body or a query parameter.

**Failure:** A key issued for one shop is accepted for a request that reads or changes another shop's data.

## 23. internal-reference-disclosure (C1)

Describe behavior in published contract text through the public API only: proto comments and `openapiv2` descriptions under `server/`, the hand-written docs and examples in `docs/config/`, and `README.md`. Flag the names of Stash's internal services, code symbols, private repositories or their file paths, internal hostnames and URLs, databases, tables, storage buckets, feature flags, internal ticket links, and references to past incidents. Say what the caller sees and does, for example "Stash rejects the request with `FAILED_PRECONDITION`", not which internal component does it. Stash's documented public hostnames, such as the API base URLs, are fine. A ticket ID in a PR title or branch name and a ticket link in a PR description follow this repository's convention and are outside this rule.

**Failure:** The public contract discloses details of Stash's internal systems to every reader of the repository.

## 24. partner-name-disclosure (C1)

Keep partner, game, and customer names out of everything this repository and its pull requests publish: proto comments under `server/`, docs and examples under `docs/`, commit messages, branch names, and PR titles and descriptions. The repository and its PRs are public, so a name written in any of them is visible to everyone. Write "the partner", "a game", or a generic example instead. Flag a name as a finding wherever it appears, including when it appears only in the PR title or description.

**Failure:** A partner, game, or customer is publicly identified through a proto comment, doc, example, commit message, branch name, or PR title or description.

## 25. shop-player-scope (C1)

Keep player-specific loyalty reads scoped by both shop and player in `LoyaltyService.GetPlayerLoyalty` and `GetPlayerLoyaltyRequest` in `server/ingress/loyalty/v1/service.proto`. Do not recast `player_id` alone as sufficient to select a loyalty standing.

**Failure:** A request for one shop exposes another shop's player's loyalty balance or tier.

## 26. endpoint-authentication (C3)

Every new operation declares the versioned `hmac` security requirement in its `openapiv2_operation`, as every operation in `server/ingress/localization/v1/service.proto` and `server/egress/shop/purchase/v1/service.proto` does, and its description says which signature header it accepts. Neither swagger declares a default security requirement, so an operation without its own is published as unauthenticated. A new operation does not accept the deprecated `legacyHmac` scheme; the `legacyHmac` description in `server/ingress/server.proto` lists the only endpoints that still do.

**Failure:** A new operation is published without its signature requirement, so a game backend implements it without verifying the caller, or a partner's generated client calls it unsigned or with the replayable legacy header.

## 27. hmac-body-integrity (C3)

Keep the versioned HMAC descriptions in `server/ingress/server.proto` and `server/egress/server.proto` bound to the exact request body, including the documented empty body for ingress GET requests. A changed signing format must not make the signature independent of the payload it authenticates.

**Failure:** A request body is altered after signing and still appears authenticated.

## 28. hmac-replay-window (C3)

Keep the signed timestamp and five-minute acceptance window in the versioned HMAC descriptions in `server/ingress/server.proto` and `server/egress/server.proto`. A changed signing format must still let receivers reject a captured old request.

**Failure:** A stale signed request is replayed and accepted outside its intended time window.

## 29. ingress-egress-key-scope (C3)

Keep the Ingress key for partner-backend-to-Stash calls and the Egress key for Stash-to-game-backend calls, as defined separately in `server/ingress/server.proto` and `server/egress/server.proto`. Do not present either key as interchangeable in API descriptions or signing examples.

**Failure:** A key issued for one API direction is reused to authenticate the other direction.

## 30. secret-example-placeholders (C3)

Every API key, signature, and token value written into an example under `server/`, `docs/config/`, or `README.md` is an obvious placeholder, such as `YOUR_API_KEY` or `{signature}`, never a value copied from a real shop, a test environment, or a log. An example that reads the reader's own key at runtime from a local file, as the signing example in `docs/config/swagger-merger-ingress-config.json` reads `~/.stash/ingress-key`, and computes the signature from it publishes no credential and is outside this rule.

**Failure:** A real credential is published in the public repository, and anyone who reads it can sign new requests or replay a captured one as that shop.

## 31. secret-observable-surfaces (C3)

Carry API keys, HMAC signatures, and session or access tokens in headers or the signed body, never in a path or query parameter of a new operation. A time-limited signed download link that a response returns, whose description says when it expires, is outside this rule.

**Failure:** A credential is copied into proxy, server, or browser logs through the request URL and can be recovered by an unintended reader.

## 32. signing-secret-exposure (C3)

Do not place a real signing key in command arguments, URLs, or logged output in examples for `docs/config/swagger-merger-ingress-config.json`. Its signing example reads the key from an owner-only file inside the signing process and says never to pass it as a command-line argument; changes to signing guidance must keep that pattern.

**Failure:** A partner's Ingress key becomes visible through a process list or captured command log.

## 33. amount-field-units (D1)

A new money amount field carries an exact amount, either integer minor units, as `RegisterPaymentRequest.PurchaseRegistration.cents` in `server/egress/shop/purchase/v1/service.proto` does, or a decimal string validated by a `pattern`, as `SpendConversionTier.prices` in `server/ingress/loyalty/v1/service.proto` does. Its ISO 4217 currency and its scale travel in the same message or in an enclosing message, and its description says so with an example and names where they come from, as `PurchaseRegistration.cents` is scaled by the enclosing request's `decimalPlaces` for its `currency`. Flag a new amount whose consumer cannot find its currency or scale anywhere in the message that carries it. `minor-unit-scale` governs the existing amount fields.

**Failure:** A consumer charges or displays a different amount than intended because the new amount's unit, scale, or currency is not carried with it.

## 34. minor-unit-scale (D1)

Preserve integer CLDR minor-unit meaning for `PriceAmountOrId.PriceAmount.cents` in `server/egress/shop/catalog/v1/service.proto`, purchase `cents`, `tax`, and `total` in `server/egress/shop/purchase/v1/service.proto`, and `Price.cents` in `server/ingress/studio/v1/service.proto`. Keep the ISO currency and applicable CLDR fraction digits tied to the same amount; do not recast these wire values as floating major units.

**Failure:** A game backend or partner charges or displays an amount different from the intended exact minor-unit price.

## 35. money-float-arithmetic (D1)

Never declare a new money amount as `float` or `double`; use an exact representation as `amount-field-units` describes. Non-money ratios such as the buff `percentage` in `server/egress/shop/catalog/v1/service.proto` are outside this rule.

**Failure:** Binary floating-point rounding changes a price, tax, or total between the side that sends it and the side that charges, grants, or displays it.

## 36. money-nonnegative-types (D1)

For a new amount or quantity that can never be negative, use an unsigned type (`uint32`, `uint64`), as the `cents`, `tax`, and `total` fields in `server/egress/shop/purchase/v1/service.proto` do. A value the contract carries as a string, such as a quantity that can exceed `uint64` (`Item.quantity` in `server/ingress/studio/v1/service.proto`) or a decimal amount (`SpendConversionTier.prices` in `server/ingress/loyalty/v1/service.proto`), has a `pattern` that admits no minus sign, as both of those do. Use a signed type only for a value that can legitimately be negative, and say in its description when it is.

**Failure:** A negative value enters a price or quantity field that has no valid negative meaning, and a consumer charges, grants, or displays it.

## 37. zero-decimal-presence (D1)

Keep `decimal_places` present even when its value is zero in `RegisterPaymentRequest`, `CancelPaymentRequest`, and `ConfirmPaymentRequest` in `server/egress/shop/purchase/v1/service.proto`. Their `optional uint32` fields and required OpenAPI descriptions encode the zero-decimal currency case; a plain proto3 scalar or JSON omission loses it.

**Failure:** A game backend rejects a valid JPY or KRW purchase because `decimalPlaces: 0` disappeared from the request.
