GOROOT := $(shell go env GOROOT)

.PHONY: all build web test fuzz lint serve clean

all: lint test build web

build:
	go build -trimpath -o picktwo ./cmd/picktwo

# The browser version: the same Go code compiled to WebAssembly.
web:
	GOOS=js GOARCH=wasm go build -trimpath -ldflags="-s -w" -o web/picktwo.wasm ./cmd/wasm
	cp "$(GOROOT)/lib/wasm/wasm_exec.js" web/wasm_exec.js

test:
	go test -race ./...
	node --test web/tests/*.test.js

fuzz:
	go test ./internal/planner -run XXX -fuzz FuzzRun -fuzztime 30s

lint:
	@test -z "$$(gofmt -l .)" || (echo "gofmt needed:"; gofmt -l .; exit 1)
	go vet ./...
	GOOS=js GOARCH=wasm go vet ./cmd/wasm

serve: web
	cd web && python3 -m http.server 8080

clean:
	rm -rf picktwo web/picktwo.wasm web/wasm_exec.js
