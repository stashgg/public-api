.PHONY: gen clean lint check

# Generate Go code from protobuf files
gen:
	./gen.sh

# Clean generated files
clean:
	rm -rf gen/

# Lint protobuf files
lint:
	cd proto && buf lint

# Format protobuf files
format:
	cd proto && buf format -w

# Update protobuf dependencies in buf.lock
update:
	cd proto && buf dep update

# Check for breaking changes (requires baseline)
breaking:
	cd proto && buf breaking --against '.git#branch=main'

# Install required tools with specific versions
install-tools:
	./install-tool.sh

# Check everything
check: lint gen
