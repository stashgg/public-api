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
2. **Polymorphism**: `CatalogItem` uses protobuf's `oneof` feature to represent multiple types of items.
3. **Big Integers**: Go's `big.Int` fields are represented as `string` fields in protobuf for maximum precision and compatibility.
4. **Timestamps**: Go's `time.Time` is mapped to `google.protobuf.Timestamp`.

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

### Special Considerations

1. **gRPC-Gateway compatibility**: Services include HTTP annotations for REST API generation.
2. **Validation rules**: Messages include validation constraints for data integrity.
3. **Unsigned integers**: Fields that can't be negative use `uint32` instead of `int32`.
4. **Dual identifiers**: Catalog items support both `guid` (optional UUID) and `product_id` (required SKU).
5. **Consolidated messages**: All response sub-messages are inlined to avoid namespace conflicts.
6. **Optional price**: When price amount or ID is not specified, the item is treated as free.
