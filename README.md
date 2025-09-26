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

See [full mapping details](proto/README.md#go-struct-to-protobuf-mapping).

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
