module rfclib

import encoding.xml

// iana_base is the canonical IANA assignments host. Each registry is
// served at a predictable URL of the form
// `${iana_base}/<registry-id>/<registry-id>.xml`, where the slug is the
// one IANA exposes in its assignments page URLs.
const iana_base = 'https://www.iana.org/assignments'

// IanaField is one named child of a `<record>` element — for instance
// `<value>404</value>` becomes `{name: "value", value: "404"}`. Sub-element
// markup inside the field is flattened to plain text so callers do not have
// to walk a partial tree.
pub struct IanaField {
pub:
	name  string
	value string
}

// IanaRef is an `<xref>` reference attached to a record. IANA uses the same
// element to point at RFCs, drafts, people, and external URIs; the discriminator
// lives in the `type` attribute (typ here).
pub struct IanaRef {
pub:
	typ  string
	data string
	text string
}

// IanaRecord is a single matched record, with its named fields and any
// references the upstream record carries. The fields preserve the order
// in which IANA published them, so callers can render the record without
// reshuffling its layout.
pub struct IanaRecord {
pub:
	fields []IanaField
	refs   []IanaRef
}

// iana_url returns the canonical URL for the XML view of an IANA registry.
// `registry` is the slug used in IANA's URLs, e.g. `http-status-codes` or
// `uri-schemes`.
pub fn iana_url(registry string) string {
	return '${iana_base}/${registry}/${registry}.xml'
}

// fetch_iana fetches the XML view of `registry` (cached) and returns the
// first record matching `code`. Matching is case-insensitive against any
// named child of the record (typically `<value>`, `<name>`, or `<number>`),
// and an integer `code` also matches numeric ranges such as `<value>105-199</value>`.
// `ErrNotFound` is returned when no record matches.
pub fn (c Client) fetch_iana(registry string, code string) !IanaRecord {
	body := c.fetch(iana_url(registry))!
	return find_iana_record(body, code) or {
		return ErrNotFound{
			resource: '${code} in ${registry}'
		}
	}
}

// refresh_iana is `fetch_iana` with the cache bypassed.
pub fn (c Client) refresh_iana(registry string, code string) !IanaRecord {
	body := c.fetch_fresh(iana_url(registry))!
	return find_iana_record(body, code) or {
		return ErrNotFound{
			resource: '${code} in ${registry}'
		}
	}
}

// find_iana_record walks every `<record>` in the document (including those
// inside nested sub-registries) and returns the first one whose any named
// child matches `code`. None when no match is found.
fn find_iana_record(body string, code string) ?IanaRecord {
	doc := xml.XMLDocument.from_string(strip_iana_pis(body)) or { return none }
	target := code.to_lower().trim_space()
	if target == '' {
		return none
	}
	for rec in doc.root.get_elements_by_tag('record') {
		fields, refs := flatten_record(rec)
		for f in fields {
			if matches_iana_field(f.value, target) {
				return IanaRecord{
					fields: fields
					refs:   refs
				}
			}
		}
	}
	return none
}

// flatten_record splits a `<record>` element's direct children into typed
// fields and reference entries. `<xref>` children are pulled out into the
// refs list because they carry attributes the field model would lose.
fn flatten_record(rec xml.XMLNode) ([]IanaField, []IanaRef) {
	mut fields := []IanaField{}
	mut refs := []IanaRef{}
	for child in rec.children {
		match child {
			xml.XMLNode {
				if child.name == 'xref' {
					refs << IanaRef{
						typ:  child.attributes['type'] or { '' }
						data: child.attributes['data'] or { '' }
						text: text_of(child).trim_space()
					}
				} else {
					fields << IanaField{
						name:  child.name
						value: text_of(child).trim_space()
					}
				}
			}
			else {}
		}
	}
	return fields, refs
}

// text_of concatenates every text node found beneath `node` in document
// order. CDATA sections are merged in transparently.
fn text_of(node xml.XMLNode) string {
	mut buf := ''
	for child in node.children {
		match child {
			string { buf += child }
			xml.XMLCData { buf += child.text }
			xml.XMLNode { buf += text_of(child) }
			else {}
		}
	}
	return buf
}

// matches_iana_field decides whether a field carries the requested code:
// either an exact (case-insensitive) string match, or a numeric range
// match such as "105-199" matching "150".
fn matches_iana_field(value string, target string) bool {
	v := value.to_lower().trim_space()
	if v == target {
		return true
	}
	return matches_numeric_range(v, target)
}

fn matches_numeric_range(value string, target string) bool {
	if !is_all_digits(target) {
		return false
	}
	dash := value.index('-') or { return false }
	lo := value[..dash].trim_space()
	hi := value[dash + 1..].trim_space()
	if !is_all_digits(lo) || !is_all_digits(hi) {
		return false
	}
	n := target.int()
	return n >= lo.int() && n <= hi.int()
}

// strip_iana_pis removes the non-prolog processing instructions IANA
// systematically prepends to its registry XML (`<?xml-stylesheet ...?>`,
// `<?xml-model ...?>`). The bundled `encoding.xml` parser refuses to
// parse a document carrying these PIs even though they are valid XML,
// so the workaround lives here rather than at every call site.
fn strip_iana_pis(body string) string {
	mut s := body
	for {
		open := s.index('<?xml-') or { break }
		close := s.index_after('?>', open) or { break }
		s = s[..open] + s[close + 2..]
	}
	return s
}

fn is_all_digits(s string) bool {
	if s == '' {
		return false
	}
	for c in s {
		if c < `0` || c > `9` {
			return false
		}
	}
	return true
}
