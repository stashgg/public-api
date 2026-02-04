#!/bin/bash

# This script generates code from protobuf files using buf.
# It generates Go code, gRPC gateway code, and OpenAPI documentation.
# The generated code is placed in the gen/ directory for use in the project.

set -ex # halt on error + print commands

# Install necessary tools
./install-tool.sh

# Add Go bin directory to PATH so protoc plugins can be found
# Go installs binaries to $GOPATH/bin or $HOME/go/bin
if [ -n "$GOPATH" ]; then
    export PATH="$GOPATH/bin:$PATH"
else
    export PATH="$HOME/go/bin:$PATH"
fi

# Clean up previous generated files
rm -rf gen/
rm -rf docs/gen/

# Generate Go code, gRPC services, gateway code, and OpenAPI docs
buf generate

# Generate TypeScript clients from OpenAPI specs
echo "Generating TypeScript clients..."
mkdir -p gen/typescript/server/shop/catalog gen/typescript/server/shop/user gen/typescript/server/shop/purchase
npx --yes swagger-typescript-api@9.3.1 -p ./gen/openapiv2/server/shop/catalog/v1/service.swagger.json -o ./gen/typescript/server/shop/catalog/ -n catalog-client.ts --route-types --module-name-index=1 --no-client
npx swagger-typescript-api@9.3.1 -p ./gen/openapiv2/server/shop/user/v1/service.swagger.json -o ./gen/typescript/server/shop/user/ -n user-client.ts --route-types --module-name-index=1 --no-client
npx swagger-typescript-api@9.3.1 -p ./gen/openapiv2/server/shop/purchase/v1/service.swagger.json -o ./gen/typescript/server/shop/purchase/ -n purchase-client.ts --route-types --module-name-index=1 --no-client

# Merge all OpenAPI specs into a single swagger file
echo "Merging Swagger files..."
mkdir -p ./docs/gen/
npx --yes swagger-merger@1.5.4 -i ./docs/config/swagger-merger-config.json -o ./docs/gen/swagger.v1.json

echo "Building Redoc static HTML file..."
npx --yes @redocly/cli@2.6.0 build-docs ./docs/gen/swagger.v1.json -o ./docs/gen/redoc.v1.html

echo "Code generation completed successfully!"
