module rfclib

// XrefEntry resolves a single cross-reference as it appears in an RFC's
// metadata. `doc_id` is the upstream string ("RFC8259", "STD0090"); `number`
// is the integer RFC number when the reference is itself an RFC, or 0 when
// it points at a higher-level series (STD, BCP) for which no per-document
// metadata endpoint exists. `title` and `pub_date` are populated only when
// the reference resolves to an RFC whose metadata was reachable.
pub struct XrefEntry {
pub:
	doc_id   string
	number   int
	title    string
	pub_date string
}

// Xref is the cross-reference graph centred on a given RFC: every list
// of related documents the RFC Editor publishes, with each entry
// resolved when possible.
pub struct Xref {
pub:
	rfc          Rfc
	obsoletes    []XrefEntry
	obsoleted_by []XrefEntry
	updates      []XrefEntry
	updated_by   []XrefEntry
	see_also     []XrefEntry
}

// parse_doc_id_number extracts the integer RFC number from an upstream
// `doc_id` string. Returns 0 when the document is not an RFC (STD/BCP
// series, FYI, etc.) or when the input is malformed.
pub fn parse_doc_id_number(doc_id string) int {
	if !doc_id.starts_with('RFC') {
		return 0
	}
	return doc_id.trim_string_left('RFC').int()
}

// resolve_refs decorates a list of upstream `doc_id` strings with the
// title and pub_date of each referenced RFC. Lookups missing from
// `cache` (because the network was unavailable or the reference is a
// non-RFC series) yield a bare entry carrying only the doc_id.
fn resolve_refs(doc_ids []string, cache map[int]Rfc) []XrefEntry {
	mut out := []XrefEntry{cap: doc_ids.len}
	for id in doc_ids {
		n := parse_doc_id_number(id)
		mut entry := XrefEntry{
			doc_id: id
			number: n
		}
		if n > 0 {
			if r := cache[n] {
				entry = XrefEntry{
					doc_id:   id
					number:   n
					title:    r.title.trim_space()
					pub_date: r.pub_date or { '' }
				}
			}
		}
		out << entry
	}
	return out
}

// build_xref assembles a typed Xref view from an RFC and a pre-populated
// map of resolved related RFCs. Splitting this out from `fetch_xref`
// lets tests exercise the resolution logic without a network round-trip.
pub fn build_xref(rfc Rfc, cache map[int]Rfc) Xref {
	return Xref{
		rfc:          rfc
		obsoletes:    resolve_refs(rfc.obsoletes, cache)
		obsoleted_by: resolve_refs(rfc.obsoleted_by, cache)
		updates:      resolve_refs(rfc.updates, cache)
		updated_by:   resolve_refs(rfc.updated_by, cache)
		see_also:     resolve_refs(rfc.see_also, cache)
	}
}

// xref returns the cross-reference graph of an RFC. The main document
// and every referenced RFC go through the cache by default, so a
// follow-up call (or an `info` after an `xref`) is served entirely from
// disk. Pass `refresh: true` to bypass the cache for the main RFC and
// every referenced metadata document.
// Non-RFC references (STD, BCP) are passed through unresolved;
// resolution failures on individual RFCs degrade gracefully to a bare
// `doc_id` entry so a single missing metadata file does not poison the
// whole graph.
pub fn (c Client) xref(number int, opts FetchOpts) !Xref {
	rfc := c.metadata(number, opts)!
	mut cache := map[int]Rfc{}
	groups := [rfc.obsoletes, rfc.obsoleted_by, rfc.updates, rfc.updated_by, rfc.see_also]
	for refs in groups {
		for id in refs {
			n := parse_doc_id_number(id)
			if n > 0 && n !in cache {
				cache[n] = c.metadata(n, opts) or { continue }
			}
		}
	}
	return build_xref(rfc, cache)
}
