module rfclib

import x.json2

// rfc_editor_base is the canonical RFC Editor host. RFC payloads (text,
// metadata JSON, errata) are mirrored at predictable URLs derived from a
// document number.
pub const rfc_editor_base = 'https://www.rfc-editor.org'

// datatracker_base is the IETF Datatracker host. It carries the live process
// state of every RFC and Internet-Draft (working group, ballots, history).
pub const datatracker_base = 'https://datatracker.ietf.org'

// Rfc is the typed view of the per-RFC metadata document published by the
// RFC Editor at `https://www.rfc-editor.org/rfc/rfcNNNN.json`.
//
// Field names match the upstream JSON schema; renames cover the few keys
// where the upstream uses a singular form (`format`) for what is in fact a
// list. `page_count` is published as a string upstream and converted on
// decode by `x.json2`.
pub struct Rfc {
pub:
	doc_id       string
	title        string
	authors      []string
	formats      []string @[json: 'format']
	page_count   ?int     @[json: 'page_count']
	pub_status   string   @[json: 'pub_status']
	status       string
	source       string
	keywords     []string
	obsoletes    []string
	obsoleted_by []string @[json: 'obsoleted_by']
	updates      []string
	updated_by   []string @[json: 'updated_by']
	see_also     []string @[json: 'see_also']
	// Fields below carry `null` upstream for the small set of "Not Issued"
	// RFCs (RFC 7000 and a handful of others) and for any document missing
	// an errata page (RFC 9767). They must therefore be optional rather
	// than plain strings to avoid a JSON decode failure.
	abstract   ?string
	pub_date   ?string @[json: 'pub_date']
	doi        ?string
	errata_url ?string @[json: 'errata_url']
	draft      ?string
}

// number returns the integer document number derived from `doc_id`
// (for example `RFC8259` -> 8259).
pub fn (r Rfc) number() int {
	return r.doc_id.trim_string_left('RFC').int()
}

// parse_rfc_number turns user input into a positive RFC number. It accepts
// the common surface forms users actually type:
//
//   "8259"       -> 8259
//   "RFC8259"    -> 8259
//   "rfc 8259"   -> 8259
//   "rfc-8259"   -> 8259
//
// Leading zeros, negative values, or trailing junk are rejected with
// ErrInvalidNumber so that we never silently accept malformed input.
pub fn parse_rfc_number(input string) !int {
	mut digits := input.to_lower().trim_space()
	if digits.starts_with('rfc') {
		digits = digits[3..].trim_left('- ')
	}
	if digits.len == 0 {
		return ErrInvalidNumber{
			value: input
		}
	}
	for c in digits {
		if c < `0` || c > `9` {
			return ErrInvalidNumber{
				value: input
			}
		}
	}
	if digits.len > 1 && digits[0] == `0` {
		return ErrInvalidNumber{
			value: input
		}
	}
	n := digits.int()
	if n <= 0 {
		return ErrInvalidNumber{
			value: input
		}
	}
	// Reject inputs that silently overflowed `int.parse`: V's `string.int`
	// clamps to `int_max` on overflow, which would turn `2147483648` into
	// `2147483647`, producing a confusing "RFC 2147483647 not found"
	// instead of "invalid RFC number".
	if n.str() != digits {
		return ErrInvalidNumber{
			value: input
		}
	}
	return n
}

// metadata_url returns the canonical URL of the JSON metadata document for
// the given RFC number.
pub fn metadata_url(number int) string {
	return '${rfc_editor_base}/rfc/rfc${number}.json'
}

// Format enumerates the document renderings published by the RFC Editor.
// `text` is universally available; `html` covers virtually every RFC; `pdf`
// and `xml` are only published for RFCs authored in xml2rfc v3 (broadly
// RFC 8650 onwards), so an `ErrNotFound` is the expected outcome on older
// documents.
pub enum Format {
	text
	html
	pdf
	xml
}

// extension returns the file-name suffix the RFC Editor uses for this format.
pub fn (f Format) extension() string {
	return match f {
		.text { 'txt' }
		.html { 'html' }
		.pdf { 'pdf' }
		.xml { 'xml' }
	}
}

// parse_format turns a user-supplied string into a Format. Accepts the
// common spellings users actually type (`text`/`txt`, `html`, `pdf`, `xml`)
// and rejects anything else with a self-describing error.
pub fn parse_format(input string) !Format {
	return match input.to_lower().trim_space() {
		'text', 'txt' { Format.text }
		'html', 'htm' { Format.html }
		'pdf' { Format.pdf }
		'xml' { Format.xml }
		else { error('unknown format: ${input} (expected: text, html, pdf, xml)') }
	}
}

// format_url returns the canonical URL of an RFC rendered in `f`.
pub fn format_url(number int, f Format) string {
	return '${rfc_editor_base}/rfc/rfc${number}.${f.extension()}'
}

// rfc_editor_info_url returns the human-facing RFC Editor information page,
// which links every published format and renders the abstract and the
// status-change history alongside the document.
pub fn rfc_editor_info_url(number int) string {
	return '${rfc_editor_base}/info/rfc${number}'
}

// datatracker_url returns the IETF Datatracker page for an RFC, where its
// working-group origin, ballots and revision history are exposed.
pub fn datatracker_url(number int) string {
	return '${datatracker_base}/doc/rfc${number}/'
}

// parse_metadata decodes a per-RFC JSON document into a typed Rfc value.
pub fn parse_metadata(body string) !Rfc {
	return json2.decode[Rfc](body)!
}

// document returns the body of an RFC in the requested format. The
// cache stores each format under its own key (the URL differs by
// extension). Pass `refresh: true` to bypass the cache.
pub fn (c Client) document(number int, f Format, opts FetchOpts) !string {
	return c.fetch_with(format_url(number, f), opts)!
}

// metadata returns the typed metadata for an RFC. By default the cache
// is consulted first; pass `refresh: true` to force a network round-trip.
pub fn (c Client) metadata(number int, opts FetchOpts) !Rfc {
	body := c.fetch_with(metadata_url(number), opts)!
	return parse_metadata(body)!
}
