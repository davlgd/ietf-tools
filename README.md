# ietf-tools

A small, modular suite of CLIs in [V](https://vlang.io) to interact with
[IETF RFCs](https://www.rfc-editor.org/) and the
[IETF Datatracker](https://datatracker.ietf.org).

The first tool, `rfc`, lets you fetch, cache and inspect any RFC from the
command line. Every CLI in the suite is built on a single shared library,
[`rfclib`](rfclib/), so behaviour around caching, identification, and error
reporting stays consistent across the suite as it grows.

## Status

- ✅ `rfc <number>` — fetch and print the plain-text RFC
- ✅ `rfc info <number>` — show metadata (status, authors, dates, obsoletes,
  errata, DOI…)
- ✅ `rfc cache path` / `rfc cache clear` — inspect and wipe the on-disk cache
- ✅ `rfc bortzmeyer <number>` — open Stéphane Bortzmeyer's French-language
  analysis of the RFC in your default browser, with `--print` to emit the URL
  instead of launching one
- ✅ `--offline` — never touch the network, only use the local cache
- 🔜 `errata`, `xref`, `track <draft>`, `iana <registry>`, `bib`

See [`docs/roadmap.md`](docs/roadmap.md) for the full plan.

## Quick start

```sh
# Build
make build              # produces ./rfc

# Read an RFC (plain text from rfc-editor.org, cached on first call)
./rfc 8259

# Show metadata (no full text)
./rfc info 8259
# RFC8259 — The JavaScript Object Notation (JSON) Data Interchange Format
#   Authors:    T. Bray, Ed.
#   Date:       December 2017
#   Status:     INTERNET STANDARD
#   …
#   Errata:     https://www.rfc-editor.org/errata/rfc8259

# Work fully offline once entries are cached
./rfc --offline info 8259
```

`rfc` accepts the common forms: `8259`, `RFC8259`, `rfc 8259`, `rfc-8259`.
Anything else (negative numbers, leading zeros, junk after digits) is
rejected explicitly.

## Architecture

```
ietf-tools/
├── main.v               # `rfc` CLI (the only binary, for now)
├── rfclib/              # Shared library; one cache + one HTTP client across the suite
│   ├── cache.v          # Content-addressed on-disk cache (sha256(url) → file)
│   ├── http.v           # net.http wrapper: User-Agent, timeouts, cache integration
│   ├── rfc.v            # Rfc struct, parse_rfc_number, URL helpers
│   ├── errors.v         # Typed errors (ErrInvalidNumber, ErrNotFound, ErrUpstream)
│   ├── *_test.v         # Unit tests
│   └── testdata/        # Real per-RFC JSON fixtures (rfc-editor.org)
├── Makefile             # build, test, fmt, vet, clean
└── v.mod
```

The shared `rfclib` is the load-bearing module: every new subcommand or
sibling CLI (e.g. a future `rfc-track` for Datatracker state) plugs into the
same `Client`, the same `Cache`, the same error types. That keeps the user's
mental model (`--offline`, `--cache-dir`, `~/.cache/ietf-tools`) identical
across the suite.

## Cache

By default the cache lives under V's `os.cache_dir()`:

| OS              | Path                                       |
| --------------- | ------------------------------------------ |
| Linux           | `$XDG_CACHE_HOME/ietf-tools` (or `~/.cache/ietf-tools`) |
| macOS           | `~/.cache/ietf-tools`                      |
| Windows         | `%LocalAppData%\ietf-tools`                |

Override with `--cache-dir <path>` on any subcommand, or wipe with
`rfc cache clear`.

Cache writes are atomic (temp file + rename), so an interrupted download
never leaves a corrupt entry under the canonical key.

## Development

```sh
make test               # run all rfclib tests
make fmt                # apply v fmt -w
make vet                # v vet
make build              # produce ./rfc (production build via clang -O)
make dev                # quick non-optimised build via tcc (faster compile)
make clean
```

`make build` uses `v -prod` so that the resulting binary is the optimised
clang build, which is what you want for daily use. `make dev` is the tcc
fast-compile path, useful while iterating on code; HTTPS may behave
differently between the two back ends, so reach for `make build` whenever
you exercise network paths.

Tests use real RFC payloads captured from `rfc-editor.org` as fixtures
(`rfclib/testdata/rfc8259.json`, `rfc7159.json`, `rfc1149.json`). HTTP tests
never hit the network: they pre-populate the cache and verify the client
serves from disk.

## Data sources

`rfc` currently talks to:

- `https://www.rfc-editor.org/rfc/rfcNNNN.json` — per-RFC metadata.
- `https://www.rfc-editor.org/rfc/rfcNNNN.txt` — plain-text rendering.

Future subcommands will add the IETF Datatracker
(`https://datatracker.ietf.org/api/v1/`), per-RFC errata
(`https://www.rfc-editor.org/errata/rfcNNNN.json`), and IANA registries
(`https://www.iana.org/protocols`).

## Acknowledgements

The schema of the metadata struct mirrors the per-RFC JSON published by the
RFC Editor; the test vectors are real payloads, kept untouched. The Python
[`ietfdata`](https://github.com/glasgow-ipl/ietfdata) library was a useful
reference for modelling the upstream data without having to copy any of its
code.

## License

Apache-2.0 — see [`LICENSE`](LICENSE).
