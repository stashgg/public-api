.PHONY: gen clean lint check

# Generate Go code from protobuf files
gen:
	./gen.sh

# Clean generated files
clean:
	rm -rf gen/

# Lint protobuf files and check formatting
lint:
	buf lint && buf format -d --exit-code

# Format protobuf files
format:
	buf format -w

# Update protobuf dependencies in buf.lock
update:
	buf dep update

# Check for breaking changes (requires baseline)
breaking:
	buf breaking --against '.git#branch=main,subdir=proto'

# Install required tools with specific versions
install-tools:
	./install-tool.sh

# Check everything
check: lint breaking gen
