# sml-httpc build (pure HTTP/1.1 client state machine)
#
#   make            build the test binary with MLton (default)
#   make test       build + run tests under MLton
#   make test-poly  run tests under Poly/ML (use-and-run; no link step)
#   make all-tests  run the suite under both compilers
#   make example    build + run the demo
#   make clean      remove build artifacts
#
# Layout B (dependent): own sources live in src/; sml-http (which itself vendors
# sml-uri) is vendored under lib/ and loaded first, then the Httpc state
# machine. This is the PURE core only; the impure socket driver lives in the
# separate sml-httpc-tool repo.

MLTON      ?= mlton
POLY       ?= poly
BIN        := bin
URIDIR     := lib/github.com/sjqtentacles/sml-uri
HTTPDIR    := lib/github.com/sjqtentacles/sml-http
TEST_MLB   := test/test.mlb
SRCS       := $(wildcard $(URIDIR)/* $(HTTPDIR)/* src/* test/*.sml) $(TEST_MLB)

.PHONY: all test poly test-poly all-tests example clean

all: $(BIN)/test-mlton

example: $(BIN)/demo
	./$(BIN)/demo

$(BIN)/demo: $(SRCS) examples/demo.sml examples/sources.mlb | $(BIN)
	$(MLTON) -output $@ examples/sources.mlb

$(BIN)/test-mlton: $(SRCS) | $(BIN)
	$(MLTON) -output $@ $(TEST_MLB)

test: $(BIN)/test-mlton
	$(BIN)/test-mlton

# Poly/ML has no native .mlb support; the suite runs at top level and exits on
# its own. Load the vendored sml-uri then sml-http sources (in dependency
# order), then the httpc sources, then the test driver.
poly test-poly:
	printf 'use "$(URIDIR)/percent.sig";\nuse "$(URIDIR)/percent.sml";\nuse "$(URIDIR)/query.sig";\nuse "$(URIDIR)/query.sml";\nuse "$(URIDIR)/uri.sig";\nuse "$(URIDIR)/uri.sml";\nuse "$(HTTPDIR)/headers.sig";\nuse "$(HTTPDIR)/headers.sml";\nuse "$(HTTPDIR)/status.sig";\nuse "$(HTTPDIR)/status.sml";\nuse "$(HTTPDIR)/http.sig";\nuse "$(HTTPDIR)/http.sml";\nuse "src/httpc.sig";\nuse "src/httpc.sml";\nuse "test/harness.sml";\nuse "test/support.sml";\nuse "test/test_build.sml";\nuse "test/test_decode.sml";\nuse "test/test_redirect.sml";\nuse "test/entry.sml";\nuse "test/main.sml";\n' | $(POLY) -q --error-exit

all-tests: test test-poly

$(BIN):
	mkdir -p $(BIN)

clean:
	rm -f $(BIN)/test-mlton $(BIN)/demo
