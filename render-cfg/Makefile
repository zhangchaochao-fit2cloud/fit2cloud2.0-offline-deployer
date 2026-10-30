PROGRAM    := ce-render-cfg
VERSION    ?= 1.0.0
GIT_COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME ?= $(shell date '+%Y-%m-%d %H:%M:%S')

LDFLAGS    := -s -w -X render-cfg/render.Version=$(VERSION) -X render-cfg/render.GitCommit=$(GIT_COMMIT) -X 'render-cfg/render.BuildTime=$(BUILD_TIME)'
GOBUILD    := GO111MODULE=on CGO_ENABLED=0 go build -a -ldflags "$(LDFLAGS)"

.PHONY: all cross linux local clean tidy

all: cross

linux:
	GOOS=linux GOARCH=amd64 $(GOBUILD) -o bin/$(PROGRAM)-amd64

local:
	$(GOBUILD) -o bin/$(PROGRAM)-local

cross: clean
	GOOS=linux GOARCH=amd64 $(GOBUILD) -o bin/$(PROGRAM)-amd64
	GOOS=linux GOARCH=arm64 $(GOBUILD) -o bin/$(PROGRAM)-arm64

tidy:
	rm -f go.sum && go mod tidy -v

clean:
	rm -rf bin
