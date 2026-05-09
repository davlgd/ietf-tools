# Build entry-points for the ietf-tools suite.
#
# Targets:
#   make build      Build the `rfc` binary in the project root.
#   make test       Run every `*_test.v` under rfclib/.
#   make fmt        Apply `v fmt -w` to the whole tree.
#   make vet        Run `v vet` (lints) on the whole tree.
#   make clean      Remove built binaries.
#
# Defaults to V's bundled mbedtls back end (smallest binary, no extra system
# dependency). If you hit a frozen SSL handshake (notably on Apple Silicon
# macOS in some configurations), opt into OpenSSL with:
#
#     brew install openssl@3
#     V_SSL_BACKEND=openssl make build

V ?= v

V_SSL_FLAGS := $(if $(filter openssl,$(V_SSL_BACKEND)),-d use_openssl,)

.PHONY: build test fmt vet clean

build:
	$(V) $(V_SSL_FLAGS) -o rfc .

test:
	$(V) test ./rfclib

fmt:
	$(V) fmt -w .

vet:
	$(V) vet .

clean:
	rm -f rfc rfc.exe
