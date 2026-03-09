#!/bin/bash

# Generates code from protobuf files (Go, OpenAPI) and API clients for TypeScript, Java, Python, C#.
# Clients are generated for both egress (gen/clients-egress/) and ingress (gen/clients-ingress/) specs.
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
  local spec="$1"
  local generator="$2"
  local output_dir="$3"
  shift 3
  npx --yes @openapitools/openapi-generator-cli generate \
    -i "$spec" \
    -g "$generator" \
    -o "$output_dir" \
    --skip-validate-spec \
    "$@"
}

generate_for_lang() {
  local lang="$1"
  local egress_out="$2"
  local ingress_out="$3"
  local py_package_egress="$4"
  local py_package_ingress="$5"

  case "$lang" in
    typescript)
      echo "Generating TypeScript client (egress)..."
      mkdir -p "$egress_out"
      run_openapi_gen ./docs/gen/swagger.v1.json typescript-fetch "$egress_out"
      echo "Generating TypeScript client (ingress)..."
      mkdir -p "$ingress_out"
      run_openapi_gen ./docs/gen/swagger.ingress.v1.json typescript-fetch "$ingress_out"
      ;;
    java)
      echo "Generating Java client (egress)..."
      mkdir -p "$egress_out"
      run_openapi_gen ./docs/gen/swagger.v1.json java "$egress_out" --additional-properties=library=native
      echo "Generating Java client (ingress)..."
      mkdir -p "$ingress_out"
      run_openapi_gen ./docs/gen/swagger.ingress.v1.json java "$ingress_out" --additional-properties=library=native
      ;;
    python)
      echo "Generating Python client (egress)..."
      mkdir -p "$egress_out"
      run_openapi_gen ./docs/gen/swagger.v1.json python "$egress_out" --additional-properties=packageName="$py_package_egress"
      echo "Generating Python client (ingress)..."
      mkdir -p "$ingress_out"
      run_openapi_gen ./docs/gen/swagger.ingress.v1.json python "$ingress_out" --additional-properties=packageName="$py_package_ingress"
      ;;
    csharp)
      echo "Generating C# client (egress)..."
      mkdir -p "$egress_out"
      run_openapi_gen ./docs/gen/swagger.v1.json csharp "$egress_out" \
        --additional-properties=library=httpclient,targetFramework=netstandard2.0
      echo "Generating C# client (ingress)..."
      mkdir -p "$ingress_out"
      run_openapi_gen ./docs/gen/swagger.ingress.v1.json csharp "$ingress_out" \
        --additional-properties=library=httpclient,targetFramework=netstandard2.0
      ;;
  esac
}

case "$LANG" in
  typescript) generate_for_lang typescript gen/clients-egress/typescript gen/clients-ingress/typescript stash_api stash_api_ingress ;;
  java)       generate_for_lang java       gen/clients-egress/java       gen/clients-ingress/java       stash_api stash_api_ingress ;;
  python)     generate_for_lang python    gen/clients-egress/python     gen/clients-ingress/python     stash_api stash_api_ingress ;;
  csharp)     generate_for_lang csharp    gen/clients-egress/csharp     gen/clients-ingress/csharp     stash_api stash_api_ingress ;;
  all)
    generate_for_lang typescript gen/clients-egress/typescript gen/clients-ingress/typescript stash_api stash_api_ingress
    generate_for_lang java       gen/clients-egress/java       gen/clients-ingress/java       stash_api stash_api_ingress
    generate_for_lang python     gen/clients-egress/python     gen/clients-ingress/python     stash_api stash_api_ingress
    generate_for_lang csharp     gen/clients-egress/csharp     gen/clients-ingress/csharp     stash_api stash_api_ingress
    ;;
esac

echo "Code generation completed successfully!"
