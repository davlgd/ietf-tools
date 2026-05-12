# ietf-tools

`rfc` is a CLI written in [V](https://vlang.io) bundling several tools
that interact with [IETF RFCs](https://www.rfc-editor.org/) and the
[IETF Datatracker](https://datatracker.ietf.org): fetch and cache RFCs,
resolve cross-references and errata, look up IANA codes, track
Internet-Drafts, and search the Datatracker — all from the command line.
Its building blocks live in [`rfclib`](rfclib/), a small shared library
that keeps caching, HTTP and error reporting consistent across every
subcommand.

## Quick start

```sh
# Build
make build              # produces ./rfc

# Read an RFC (plain text from rfc-editor.org, cached on first call)
./rfc 8259

# Pick a different rendering: text (default), html, pdf, xml
./rfc -f html 8259
./rfc -f pdf 9000 > rfc9000.pdf

# Show metadata (status, dates, obsoletes, errata, RFC Editor + Datatracker links)
./rfc info 8259

# Cross-reference graph (each related RFC resolved to its title)
./rfc xref 8259

# Errata reported against an RFC
./rfc errata 8259

# IETF Datatracker state of an Internet-Draft
./rfc track draft-ietf-quic-transport

# Look up a code in any IANA registry XML
./rfc iana http-status-codes 404
./rfc iana uri-schemes ssh

# List recently published RFCs from the RSS feed (-f json for piping)
./rfc latest

# Search by title token(s); add -s to filter by std_level, -n to cap, -f json
./rfc search tls 1.3
./rfc search -s ps tls 1.3

# Open Stéphane Bortzmeyer's analysis in your browser when one exists
./rfc bortzmeyer 8259

# Inspect or wipe the local cache
./rfc cache path
./rfc cache clear

# Work fully offline once entries are cached
./rfc --offline info 8259
```

`rfc` accepts the common forms: `8259`, `RFC8259`, `rfc 8259`, `rfc-8259`.
Anything else (negative numbers, leading zeros, junk after digits) is
rejected explicitly.

## Architecture

The shared `rfclib` is the load-bearing module: every subcommand and
every future sibling CLI plugs into the same `Client`, the same
`Cache`, the same `FetchOpts`/typed errors. That keeps the user's
mental model (`--offline`, `--cache-dir`, `--refresh`,
`~/.cache/ietf-tools`) identical across the suite.

## Cache

By default the cache lives under V's `os.cache_dir()`, which honours
`$XDG_CACHE_HOME` everywhere (V's stdlib applies the XDG convention
uniformly, including on macOS and Windows):

| Platform          | Path                                                        |
| ----------------- | ----------------------------------------------------------- |
| `$XDG_CACHE_HOME` | `$XDG_CACHE_HOME/ietf-tools`                                |
| Linux / macOS     | `~/.cache/ietf-tools` when `$XDG_CACHE_HOME` is unset       |
| Windows           | `%USERPROFILE%\.cache\ietf-tools` when `%XDG_CACHE_HOME%` is unset |

Show or override the path:

```sh
rfc cache path                       # print the active cache directory
rfc --cache-dir /tmp/rfc info 8259   # override per invocation
rfc cache clear                      # wipe every entry
```

Cache writes are atomic (temp file + rename), so an interrupted download
never leaves a corrupt entry under the canonical key.

## Development

```sh
make test               # run every *_test.v under rfclib/ and at the root
make fmt                # apply v fmt -w
make vet                # v vet
make build              # produce ./rfc (production build via clang -O)
make dev                # quick non-optimised build via tcc (faster compile)
make install            # install ./rfc to $(PREFIX)/bin (default /usr/local)
make uninstall          # remove the installed rfc binary
make clean
```

`PREFIX` and `DESTDIR` are honoured by `install`/`uninstall`, so
distribution packagers can do `make install DESTDIR=$pkgdir PREFIX=/usr`.

`make build` uses `v -prod` so that the resulting binary is the optimised
clang build, which is what you want for daily use. `make dev` is the tcc
fast-compile path, useful while iterating on code; HTTPS may behave
differently between the two back ends, so reach for `make build` whenever
you exercise network paths.

Tests use real upstream payloads as fixtures (`rfclib/testdata/`). HTTP
tests never hit the network: they pre-populate the cache and verify the
client serves from disk.

CI runs `v fmt -verify`, `v vet`, `v test` and `v -prod` on every push and
pull request, across Linux x86_64, Linux ARM64 and macOS ARM64. See
[`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Data sources

`rfc` currently talks to:

- `https://www.rfc-editor.org/rfc/rfcNNNN.{json,txt,html,pdf,xml}` —
  per-RFC metadata and renderings (PDF/XML only for xml2rfc-v3 era
  documents).
- `https://www.rfc-editor.org/rfcrss.xml` — RSS 2.0 feed of recent RFCs.
- `https://www.rfc-editor.org/errata.json` — global errata catalogue,
  filtered locally by RFC number.
- `https://datatracker.ietf.org/api/v1/doc/document/` — Datatracker
  search endpoint plus per-draft state.
- `https://datatracker.ietf.org/api/v1/doc/state/` — Datatracker state
  catalogue, joined locally against each draft's state URIs.
- `https://www.iana.org/assignments/<reg>/<reg>.xml` — IANA registries.
- `https://www.bortzmeyer.org/<number>.html` — Bortzmeyer's per-RFC
  analysis, reached via a HEAD probe + browser launch.

## License

Apache-2.0 — see [`LICENSE`](LICENSE)
