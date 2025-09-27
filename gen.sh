#!/bin/bash

# This script generates code from protobuf files using buf.
# It generates Go code, gRPC gateway code, and OpenAPI documentation.
# The generated code is placed in the gen/ directory for use in the project.

set -ex # halt on error + print commands

# Install necessary tools
./install-tool.sh

# Clean up previous generated files
rm -rf gen/

# Generate Go code, gRPC services, gateway code, and OpenAPI docs
buf generate

# Generate TypeScript clients from OpenAPI specs
cd ..  # Go back to repo root
echo "Generating TypeScript clients..."
mkdir -p gen/typescript/server/shop/catalog gen/typescript/server/shop/user gen/typescript/server/shop/purchase
npx swagger-typescript-api@9.3.1 -p ./gen/openapiv2/server/shop/catalog/v1/service.swagger.json -o ./gen/typescript/server/shop/catalog/ -n catalog-client.ts --route-types --module-name-index=1 --no-client
npx swagger-typescript-api@9.3.1 -p ./gen/openapiv2/server/shop/user/v1/service.swagger.json -o ./gen/typescript/server/shop/user/ -n user-client.ts --route-types --module-name-index=1 --no-client
npx swagger-typescript-api@9.3.1 -p ./gen/openapiv2/server/shop/purchase/v1/service.swagger.json -o ./gen/typescript/server/shop/purchase/ -n purchase-client.ts --route-types --module-name-index=1 --no-client

echo "Code generation completed successfully!"
