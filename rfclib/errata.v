module rfclib

import x.json2

// errata_url is the global errata catalogue published by the RFC Editor.
// The endpoint serves *every* erratum across the entire RFC corpus (~11 MB
// JSON, ~7900 entries as of 2026); rfclib downloads it once, caches it on
// disk, and filters per-RFC locally. The full payload is the only JSON
// surface the RFC Editor exposes — the per-RFC pages (`/errata/rfcNNNN`)
// only render HTML.
const errata_url = '${rfc_editor_base}/errata.json'

// Erratum is the typed view of a single entry from the RFC Editor errata
// catalogue. Fields that the upstream may emit as `null` are typed
// `?string` so the parser does not crash on real payloads.
pub struct Erratum {
pub:
	errata_id          string @[json: 'errata_id']
	doc_id             string @[json: 'doc-id']
	errata_status_code string @[json: 'errata_status_code']
	errata_type_code   string @[json: 'errata_type_code']
	submit_date        string @[json: 'submit_date']
	submitter_name     string @[json: 'submitter_name']
	verifier_id        string @[json: 'verifier_id']
	// Nullable fields observed in the public catalogue (counts as of
	// 2026-05): verifier_name (1155), correct_text (175), notes (304),
	// section (36), orig_text (118), update_date (389).
	section       ?string @[json: 'section']
	orig_text     ?string @[json: 'orig_text']
	correct_text  ?string @[json: 'correct_text']
	notes         ?string @[json: 'notes']
	verifier_name ?string @[json: 'verifier_name']
	update_date   ?string @[json: 'update_date']
}

// number returns the integer document number derived from `doc_id`
// (for example `RFC8259` -> 8259). Returns 0 when the document is not an
// RFC (some catalogue entries reference non-RFC documents historically).
pub fn (e Erratum) number() int {
	return e.doc_id.trim_string_left('RFC').int()
}

// parse_errata decodes the RFC Editor errata catalogue (top-level JSON
// array). Callers normally use `Client.errata_for` instead, which both
// fetches and filters the result by RFC number.
pub fn parse_errata(body string) ![]Erratum {
	return json2.decode[[]Erratum](body)!
}

// errata_for returns every erratum reported against `number`, fetching the
// global catalogue through the cache and filtering locally. Results are
// returned in the order published upstream (which is errata_id ascending).
pub fn (c Client) errata_for(number int) ![]Erratum {
	body := c.fetch(errata_url)!
	return filter_errata(parse_errata(body)!, number)
}

// refresh_errata_for redownloads the global catalogue (overwriting the
// cached copy) before filtering. Use it when the cache is suspected stale.
pub fn (c Client) refresh_errata_for(number int) ![]Erratum {
	body := c.fetch_fresh(errata_url)!
	return filter_errata(parse_errata(body)!, number)
}

fn filter_errata(all []Erratum, number int) []Erratum {
	target := 'RFC${number}'
	mut hits := []Erratum{}
	for e in all {
		if e.doc_id == target {
			hits << e
		}
	}
	return hits
}
