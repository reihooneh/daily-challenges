.PHONY: build test fuzz lint clean

build:
	go build -trimpath -o build/bowball ./cmd/bowball

test:
	go test -race -count=1 ./...

fuzz:
	go test -run=NONE -fuzz=FuzzParse -fuzztime=30s ./internal/bowball

lint:
	gofmt -l . | (! grep .)
	go vet ./...

clean:
	rm -rf build
