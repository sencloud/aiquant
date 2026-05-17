.PHONY: tidy build run-api run-scheduler run-pusher fmt vet test clean

BIN := bin/finme-server
PKG := ./...
LDFLAGS := -ldflags "-s -w -X main.Version=$(shell git rev-parse --short HEAD 2>/dev/null || echo dev)"

tidy:
	go mod tidy

build:
	mkdir -p bin
	CGO_ENABLED=0 go build $(LDFLAGS) -o $(BIN) ./cmd/finme-server

run-api: build
	$(BIN) api --config ./config/config.toml

run-scheduler: build
	$(BIN) scheduler --config ./config/config.toml

run-pusher: build
	$(BIN) pusher --config ./config/config.toml

fmt:
	gofmt -s -w .

vet:
	go vet $(PKG)

test:
	go test -race -count=1 $(PKG)

clean:
	rm -rf bin data
