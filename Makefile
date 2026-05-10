# Build entry-points for the ietf-tools suite.
#
# Targets:
#   make build      Build a production `rfc` binary in the project root.
#   make dev        Quick non-optimised build (tcc), useful while iterating.
#   make test       Run every `*_test.v` under rfclib/.
#   make fmt        Apply `v fmt -w` to the whole tree.
#   make vet        Run `v vet` (lints) on the whole tree.
#   make install    Install `rfc` to $(PREFIX)/bin (default: /usr/local).
#   make uninstall  Remove the installed `rfc` binary.
#   make clean      Remove built binaries.

V ?= v
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

.PHONY: build dev test fmt vet install uninstall clean

build:
	$(V) -prod -o rfc .

dev:
	$(V) -o rfc .

test:
	$(V) test ./rfclib

fmt:
	$(V) fmt -w .

vet:
	$(V) vet .

install: build
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 rfc $(DESTDIR)$(BINDIR)/rfc

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/rfc

clean:
	rm -f rfc rfc.exe
