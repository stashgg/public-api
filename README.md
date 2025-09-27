# public-api

Used to store protos and auto-generated clients for public- and external-facing APIs.

## Structure

- `/proto/server` contains the protobuf definitions for the server-side shop APIs communicating with the game backend.
- `/gen` contains the auto-generated API clients and swagger files used to validate the protos (each binary using these protos should generate their own clients).

### Shop Services

- `server/shop/catalog/v1/` - Catalog-related protobuf definitions
  - `enums.proto` - Enumeration definitions (CatalogItemType, ChainLinkStatus)
  - `service.proto` - Catalog gRPC service definitions and request/response messages

- `server/shop/purchase/v1/` - Purchase/transaction management protobuf definitions
  - `enums.proto` - Enumeration definitions (Platform, PurchaseSource, PurchaseRegistrationStatus, CancellationStatus)
  - `service.proto` - Purchase gRPC service definitions and request/response messages

- `server/shop/user/v1/` - User/player management protobuf definitions
  - `service.proto` - User gRPC service definitions and request/response messages

## Key Design Decisions

1. **Field Names**: All protobuf field names closely match the JSON tags from the original alpha API schema.
2. **Polymorphism**: The original `CatalogItem` interface is implemented using protobuf's `oneof` feature in the `CatalogItem` message.
3. **Big Integers**: Go's `big.Int` fields are represented as `string` fields in protobuf for maximum precision and compatibility.
4. **Optional Fields**: Protobuf 3's optional fields are used for fields that were pointers in the original Go structs.
5. **Timestamps**: Go's `time.Time` is mapped to `google.protobuf.Timestamp`.

## Code Generation

Generate clients (for validation purposes):

```bash
make gen
# or directly:
./gen.sh
```

Lint protobuf files:

```bash
make lint
```

Format protobuf files:

```bash
make format
```

## Field Mapping Reference

See [full mapping details](#go-struct-to-protobuf-mapping).

### Original Go JSON Tag → Proto Field

- `json:"guid"` → `guid`
- `json:"image"` → `image` (not `image_url`)
- `json:"imageUrl"` → `image_url`
- `json:"unitImage"` → `unit_image`
- `json:"max_purchasable"` → `max_purchasable`
- `json:"maxPurchasable"` → `max_purchasable` (camelCase → snake_case for consistency)
- `json:"bundleImage"` → `bundle_image`
- `json:"revealButton"` → `reveal_button`
- `json:"leftDecal"` → `left_decal`
- `json:"rightDecal"` → `right_decal`

## Generated Output

To validate correctness of the protos, this repo comes with commands to generate:

- Go structs and gRPC client/server code
- gRPC-Gateway HTTP/JSON bindings
- OpenAPI v2 (swagger) documentation

Generated files are placed in the `gen/` directory and are not committed to version control. Instead, each project using these protos should build their own clients as needed.

### Generated Output Structure

Running `make gen` from the repo root creates:

```
gen/
├── proto/                    # Generated Go code
│   └── server/shop/
│       ├── catalog/v1/      # Catalog service Go structs & gRPC
│       ├── purchase/v1/     # Purchase service Go structs & gRPC
│       └── user/v1/        # User service Go structs & gRPC
├── openapiv2/              # OpenAPI/Swagger documentation
│   └── server/shop/
│       ├── catalog/v1/     # service.swagger.json (rich) + enums.swagger.json (minimal)
│       ├── purchase/v1/    # service.swagger.json (rich) + enums.swagger.json (minimal)
│       └── user/v1/       # service.swagger.json (rich)
└── typescript/             # TypeScript API clients
    └── server/shop/
        ├── catalog/        # catalog-client.ts
        ├── purchase/       # purchase-client.ts
        └── user/          # user-client.ts
```

### About Swagger Files

- **Service files** (`service.swagger.json`) are rich with API endpoints and full documentation
- **Non-service files** (like `common.swagger.json`, `enums.swagger.json`) are minimal because they only contain type definitions, not REST endpoints
- This is normal behavior - only protobuf `service` definitions generate REST APIs

## REST API Endpoints

The gRPC services are automatically exposed as REST endpoints via grpc-gateway:

### Catalog Service (`server.shop.catalog.v1.CatalogService`)
- **GET** `/api/v1/catalog` - Retrieve the product catalog

### Purchase Service (`server.shop.purchase.v1.PurchaseService`)
- **POST** `/api/v1/purchase/register` - Register purchase intent
  ```json
  {
    "user_id": "string (required)",
    "transaction_id": "string (required)",
    "platform": "Platform enum (optional: 0, 1, 2, 3)",
    "browser": "string (optional, e.g., 'Chrome/91.0', 'any')",
    "device_id": "string (optional, for fraud prevention)", 
    "source": "PurchaseSource enum (optional: 0, 1, 2)",
    "registrations": [
      {
        "product_id": "string (SKU, required if guid not present)",
        "guid": "string (UUID, required if product_id not present)",
        "price_id": "string (required if price not present, typically same as product_id SKU)",
        "price.currency": "string (ISO-4217, e.g., 'USD')",
        "price.amount": "uint32 (required if price_id not present, integer, e.g., 999 for $9.99)",
        "quantity": "uint32 (required, > 0)"
      }
    ]
  }
  ```

- **POST** `/api/v1/purchase/cancel` - Cancel pending purchase
  ```json
  {
    "user_id": "string (required)",
    "transaction_id": "string (required)"
  }
  Response: {
    "status": "CANCELLED | TRANSACTION_NOT_FOUND | ALREADY_COMPLETED",
    "message": "string (optional)",
    "transaction_id": "string"
  }
  ```

- **POST** `/api/v1/purchase/confirm` - Confirm and complete purchase
  ```json
  {
    "user_id": "string (required)",
    "transaction_id": "string (required)",
    "extra_in_game_currency": "uint32 (optional)",
    "extra_loyalty_points": "uint32 (optional)",
    "extra_loyalty_credits": "uint32 (optional)"
  }
  Response: {
    "results": [
      {
        "product_id": "string (SKU, required if guid not present)",
        "guid": "string (UUID, required if product_id not present)",
      }
    ],
    "transaction_id": "string"
  }
  ```

### User Service (`server.shop.user.v1.UserService`)
- **POST** `/api/v1/user` - Get or create a player
  ```json
  {
    "player_id": "string (required, min_len=1)"
  }
  ```

## JSON Format Handling

### Enum Values
- **Recommended**: Always emit enum values as integers for [wire-safety](https://protobuf.dev/programming-guides/json/#wire-safe) when adding new enum values
- **In JSON**: Parsers accept both enum names (strings) and integer values, but integers are safer for schema evolution
- **Example**: `"platform": 1` (integer) is preferred over `"platform": "PLATFORM_IOS"` (string)

### Field Names
- **Default behavior**: Protobuf JSON converts field names to lowerCamelCase (e.g., `product_id` → `productId`)  
- **Parser requirement**: Must accept both lowerCamelCase and original proto field names
- **Implementation options**: Can be configured to use original proto field names instead
- **More details**: See [JSON Options documentation](https://protobuf.dev/programming-guides/json/#json-options)

## Validation Rules

The protobuf definitions include comprehensive validation:

- **String fields**: Required fields have `min_len=1` validation
- **Currency codes**: Exactly 3 characters (e.g., "USD", "EUR")
- **Price amounts**: Must match decimal number pattern
- **Unsigned integers**: Player level, in-game currency, and purchase limits use `uint32`
- **Dual identifiers**: Catalog items have both `guid` (optional UUID v4) and `product_id` (required SKU)
- **UUID validation**: GUID fields use `validate.rules.string.uuid = true` constraint
- **Consolidated structure**: Response messages inline all sub-types to prevent namespace conflicts

## Purchase Flow

The purchase system follows a 3-step transaction model:

1. **Register** (`/api/v1/purchase/register`) - Create purchase intent
   - Validates product availability and pricing
   - Returns offer statuses for each item
   - Creates transaction context

2. **Cancel** (`/api/v1/purchase/cancel`) - Cancel pending purchase (optional)
   - Cancels the transaction if payment fails or user backs out
   - Frees up reserved inventory
   
3. **Confirm** (`/api/v1/purchase/confirm`) - Complete the purchase
   - Processes payment and delivers items
   - Supports optional bonus rewards (in-game currency, loyalty points/credits)
   - Returns final purchase results

## Go Struct to Protobuf Mapping

This document shows the exact mapping from the original Go structs to the protobuf definitions.

### Enums

| Go Type                      | Go Constants                                              | Proto Enum                   | Proto Values                                                                                                                |
| ---------------------------- | --------------------------------------------------------- | ---------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `NonPurchasableItemType`     | `""`, `"banner"`                                          | `NonPurchasableItemType`     | `NON_PURCHASABLE_ITEM_TYPE_UNSPECIFIED`, `NON_PURCHASABLE_ITEM_TYPE_BANNER`                                                |
| `ChainLinkStatus`            | `"claimed"`, `"unlocked"`, `"locked"`                     | `ChainLinkStatus`            | `CLAIMED`, `UNLOCKED`, `LOCKED`                                                                                             |
| `Platform`                   | N/A (new)                                                 | `Platform`                   | `PLATFORM_UNSPECIFIED`, `PLATFORM_IOS`, `PLATFORM_ANDROID`, `PLATFORM_WEBSTORE`                                           |
| `PurchaseSource`             | N/A (new)                                                 | `PurchaseSource`             | `PURCHASE_SOURCE_UNSPECIFIED`, `PURCHASE_SOURCE_CART`, `PURCHASE_SOURCE_DIRECT`                                            |
| `PurchaseRegistrationStatus` | N/A (new)                                                 | `PurchaseRegistrationStatus` | `PURCHASE_REGISTRATION_STATUS_UNSPECIFIED`, `SUCCESS_REGISTERED`, `FAILED_INVALID_OFFER`, etc.                             |
| `CancellationStatus`         | N/A (new)                                                 | `CancellationStatus`         | `CANCELLATION_STATUS_UNSPECIFIED`, `SUCCESS_CANCELLED`, `FAILED_TRANSACTION_NOT_FOUND`, `FAILED_ALREADY_COMPLETED`, etc. |

### Common Types

| Go Struct    | Go Field                 | JSON Tag                      | Proto Message | Proto Field                   |
| ------------ | ------------------------ | ----------------------------- | ------------- | ----------------------------- |
| `Banner`     | `Text string`            | `"text"`                      | `Banner`      | `string text = 1`             |
| `Badge`      | `Text string`            | `"text"`                      | `Badge`       | `string text = 1`             |
| `Button`     | `Text string`            | `"text"`                      | `Button`      | `string text = 1`             |
| `Background` | `ImageUrl string`        | `"imageUrl,omitempty"`        | `Background`  | `string image_url = 1`        |
| `Background` | `BackgroundStyle string` | `"backgroundStyle,omitempty"` | `Background`  | `string background_style = 2` |
| `Decal`      | `ImageUrl string`        | `"imageUrl"`                  | `Decal`       | `string image_url = 1`        |
| `Tooltip`    | `Text string`            | `"text,omitempty"`            | `Tooltip`     | `string text = 1`             |
| `Price`      | `Currency string`        | `"currency"`                  | `Price`       | `string currency = 1`         |
| `Price`      | `Amount string`          | `"amount"`                    | `Price`       | `string amount = 2`           |

### Content Types

| Go Struct        | Go Field               | JSON Tag                | Proto Message    | Proto Field                      |
| ---------------- | ---------------------- | ----------------------- | ---------------- | -------------------------------- |
| `ContentItem`    | `Name string`          | `"name"`                | `ContentItem`    | `string name = 1`                |
| `ContentItem`    | `Description string`   | `"description"`         | `ContentItem`    | `string description = 2`         |
| `ContentItem`    | `ImageUrl string`      | `"image"`               | `ContentItem`    | `string image = 3`               |
| `ContentItem`    | `Quantity *big.Int`    | `"quantity"`            | `ContentItem`    | `string quantity = 4`            |
| `ObtainableItem` | `Name string`          | `"name"`                | `ObtainableItem` | `string name = 1`                |
| `ObtainableItem` | `ImageUrl string`      | `"image"`               | `ObtainableItem` | `string image = 2`               |
| `ObtainableItem` | `Quantity *big.Int`    | `"quantity"`            | `ObtainableItem` | `string quantity = 3`            |
| `ObtainableItem` | `UnitImageUrl *string` | `"unitImage,omitempty"` | `ObtainableItem` | `optional string unit_image = 4` |

### Main Item Types

| Go Struct         | Go Field                            | JSON Tag                 | Proto Message     | Proto Field                                     |
| ----------------- | ----------------------------------- | ------------------------ | ----------------- | ----------------------------------------------- |
| `PurchasableItem` | `Id string`                         | `"guid"`                 | `PurchasableItem` | `string guid = 1`                               |
| `PurchasableItem` | `Type CatalogItemType`              | `"type"`                 | `PurchasableItem` | `CatalogItemType type = 2`                      |
| `PurchasableItem` | `Name string`                       | `"name"`                 | `PurchasableItem` | `string name = 3`                               |
| `PurchasableItem` | `Description string`                | `"description"`          | `PurchasableItem` | `string description = 4`                        |
| `PurchasableItem` | `ImageUrl string`                   | `"image"`                | `PurchasableItem` | `string image = 5`                              |
| `PurchasableItem` | `MaxPurchasable *uint32`            | `"max_purchasable"`      | `PurchasableItem` | `optional uint32 max_purchasable = 6`           |
| `PurchasableItem` | `Price Price`                       | `"price"`                | `PurchasableItem` | `Price price = 7`                               |
| `PurchasableItem` | `Attributes *PurchasableAttributes` | `"attributes,omitempty"` | `PurchasableItem` | `optional PurchasableAttributes attributes = 8` |
| `PurchasableItem` | `Contents []ContentItem`            | `"contents"`             | `PurchasableItem` | `repeated ContentItem contents = 9`             |

### Offer Chain Types

| Go Struct        | Go Field                 | JSON Tag                  | Proto Message    | Proto Field                                         |
| ---------------- | ------------------------ | ------------------------- | ---------------- | --------------------------------------------------- |
| `OfferChainLink` | `Id string`              | `"guid"`                  | `OfferChainLink` | `string guid = 1`                                   |
| `OfferChainLink` | `Price *Price`           | `"price"`                 | `OfferChainLink` | `optional Price price = 2`                          |
| `OfferChainLink` | `MaxPurchasable *uint32` | `"maxPurchasable"`        | `OfferChainLink` | `optional uint32 max_purchasable = 3`               |
| `OfferChainLink` | `Items []ObtainableItem` | `"items"`                 | `OfferChainLink` | `repeated ObtainableItem items = 4`                 |
| `OfferChainLink` | `Status ChainLinkStatus` | `"status"`                | `OfferChainLink` | `ChainLinkStatus status = 5`                        |
| `OfferChainLink` | `BundleImageUrl *string` | `"bundleImage,omitempty"` | `OfferChainLink` | `optional string bundle_image = 6`                  |
| `OfferChainItem` | `Id string`              | `"guid"`                  | `OfferChainItem` | `string guid = 1`                                   |
| `OfferChainItem` | `Type CatalogItemType`   | `"type"`                  | `OfferChainItem` | `CatalogItemType type = 2`                          |
| `OfferChainItem` | `Name string`            | `"name"`                  | `OfferChainItem` | `string name = 3`                                   |
| `OfferChainItem` | `Description string`     | `"description"`           | `OfferChainItem` | `string description = 4`                            |
| `OfferChainItem` | `Expiration *time.Time`  | `"expiration"`            | `OfferChainItem` | `optional google.protobuf.Timestamp expiration = 5` |
| `OfferChainItem` | `Repeatable bool`        | `"repeatable"`            | `OfferChainItem` | `bool repeatable = 6`                               |
| `OfferChainItem` | `Links []OfferChainLink` | `"links"`                 | `OfferChainItem` | `repeated OfferChainLink links = 7`                 |
| `OfferChainItem` | `Banner *ChainBanner`    | `"banner,omitempty"`      | `OfferChainItem` | `optional ChainBanner banner = 8`                   |

### Non-Purchasable Types

| Go Struct            | Go Field                               | JSON Tag                 | Proto Message        | Proto Field                                        |
| -------------------- | -------------------------------------- | ------------------------ | -------------------- | -------------------------------------------------- |
| `NonPurchasableItem` | `Id string`                            | `"guid"`                 | `NonPurchasableItem` | `string guid = 1`                                  |
| `NonPurchasableItem` | `Type CatalogItemType`                 | `"type"`                 | `NonPurchasableItem` | `CatalogItemType type = 2`                         |
| `NonPurchasableItem` | `Title string`                         | `"title"`                | `NonPurchasableItem` | `string title = 3`                                 |
| `NonPurchasableItem` | `Body string`                          | `"body"`                 | `NonPurchasableItem` | `string body = 4`                                  |
| `NonPurchasableItem` | `Attributes *NonPurchasableAttributes` | `"attributes,omitempty"` | `NonPurchasableItem` | `optional NonPurchasableAttributes attributes = 5` |
| `NonPurchasableItem` | `Contents []NonPurchasableContentItem` | `"contents"`             | `NonPurchasableItem` | `repeated NonPurchasableContentItem contents = 6`  |

### Top-Level Catalog

| Go Struct | Go Field             | JSON Tag   | Proto Message | Proto Field                      |
| --------- | -------------------- | ---------- | ------------- | -------------------------------- |
| `Row`     | `Header string`      | `"header"` | `Row`         | `string header = 1`              |
| `Row`     | `Items CatalogItems` | `"items"`  | `Row`         | `repeated CatalogItem items = 2` |
| `Catalog` | `Rows []Row`         | `"rows"`   | `Catalog`     | `repeated Row rows = 1`          |

### Polymorphic Handling

The original Go implementation used an interface `CatalogItem` with custom JSON marshaling/unmarshaling to handle different item types. In protobuf, this is replaced with:

```protobuf
message CatalogItem {
    oneof item {
        PurchasableItem purchasable_item = 1;
        OfferChainItem offer_chain_item = 2;
        NonPurchasableItem non_purchasable_item = 3;
    }
}
```

### Special Considerations

1. **big.Int → string**: Go's `big.Int` type is represented as `string` in protobuf for precision.
2. **Pointers → optional**: Go pointer fields become `optional` fields in proto3.
3. **time.Time → Timestamp**: Go's `time.Time` becomes `google.protobuf.Timestamp`.
4. **Interfaces → oneof**: Go interfaces become protobuf `oneof` unions.
5. **JSON field names preserved**: All protobuf field names match the original JSON tags exactly.
6. **gRPC-Gateway compatibility**: Services include HTTP annotations for REST API generation.
7. **Validation rules**: Messages include validation constraints for data integrity.
8. **Unsigned integers**: Fields that can't be negative use `uint32` instead of `int32`.
9. **Dual identifiers**: Catalog items support both `guid` (optional UUID) and `product_id` (required SKU).
10. **Consolidated messages**: All response sub-messages are inlined to avoid namespace conflicts.
