#!/bin/bash

# Install protobuf and gRPC code generation tools with specific versions
# This ensures consistent builds across different environments

set -e # halt on error

echo "Installing protobuf and gRPC tools..."

go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.5
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1
go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@v2.26.1
go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-openapiv2@v2.26.1
go install github.com/envoyproxy/protoc-gen-validate@v1.2.1

echo "Tools installed successfully!"
