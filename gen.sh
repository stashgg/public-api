#!/bin/bash

# Generates code from protobuf files (Go, OpenAPI) and API clients for TypeScript, Java, Python, C#.
# Usage: ./gen.sh [language]
#   language: typescript | java | python | csharp | all (default: all)

set -e

usage() {
  echo "Usage: ./gen.sh [language]"
  echo "  language: typescript | java | python | csharp | all (default: all)"
  exit 1
}

LANG="${1:-all}"
case "$LANG" in
  typescript|java|python|csharp|all) ;;
  *) usage ;;
esac

# Add Go bin to PATH for protoc plugins
if [ -n "$GOPATH" ]; then
  export PATH="$GOPATH/bin:$PATH"
else
  export PATH="$HOME/go/bin:$PATH"
fi

./install-tool.sh

rm -rf gen/
rm -rf docs/gen/

echo "Generating Go code and OpenAPI specs..."
buf generate

echo "Merging Swagger files..."
mkdir -p docs/gen
npx --yes swagger-merger@1.5.4 -i ./docs/config/swagger-merger-config.json -o ./docs/gen/swagger.v1.json
npx --yes swagger-merger@1.5.4 -i ./docs/config/swagger-merger-ingress-config.json -o ./docs/gen/swagger.ingress.v1.json

echo "Building Redoc docs..."
npx --yes @redocly/cli@2.6.0 build-docs ./docs/gen/swagger.v1.json -o ./docs/gen/redoc.v1.html
npx --yes @redocly/cli@2.6.0 build-docs ./docs/gen/swagger.ingress.v1.json -o ./docs/gen/redoc.ingress.v1.html

check_java() {
  if ! command -v java &>/dev/null; then
    echo "Java 11+ is required for client generation. Install Java and try again."
    exit 1
  fi
}

run_openapi_gen() {
  check_java
  local generator="$1"
  local output_dir="$2"
  shift 2
  npx --yes @openapitools/openapi-generator-cli generate \
    -i ./docs/gen/swagger.v1.json \
    -g "$generator" \
    -o "$output_dir" \
    --skip-validate-spec \
    "$@"
}

generate_typescript() {
  echo "Generating TypeScript client..."
  mkdir -p gen/clients/typescript
  run_openapi_gen typescript-fetch gen/clients/typescript
}

generate_java() {
  echo "Generating Java client..."
  mkdir -p gen/clients/java
  run_openapi_gen java gen/clients/java --additional-properties=library=native
}

generate_python() {
  echo "Generating Python client..."
  mkdir -p gen/clients/python
  run_openapi_gen python gen/clients/python --additional-properties=packageName=stash_api
}

generate_csharp() {
  echo "Generating C# client..."
  mkdir -p gen/clients/csharp
  run_openapi_gen csharp gen/clients/csharp \
    --additional-properties=library=httpclient,targetFramework=netstandard2.0
}

case "$LANG" in
  typescript) generate_typescript ;;
  java)       generate_java ;;
  python)     generate_python ;;
  csharp)     generate_csharp ;;
  all)
    generate_typescript
    generate_java
    generate_python
    generate_csharp
    ;;
esac

echo "Code generation completed successfully!"
