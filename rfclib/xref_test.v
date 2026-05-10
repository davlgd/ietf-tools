module rfclib

import os

fn xref_fixture(name string) string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', name)
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn test_parse_doc_id_number() {
	assert parse_doc_id_number('RFC8259') == 8259
	assert parse_doc_id_number('RFC0793') == 793
	assert parse_doc_id_number('RFC1') == 1
	// Non-RFC series collapse to 0 — they have no per-document JSON endpoint.
	assert parse_doc_id_number('STD0090') == 0
	assert parse_doc_id_number('BCP0014') == 0
	assert parse_doc_id_number('') == 0
	assert parse_doc_id_number('garbage') == 0
}

fn test_build_xref_resolves_known_refs_and_passes_unknown_through() {
	rfc8259 := parse_metadata(xref_fixture('rfc8259.json')) or { panic(err) }
	rfc7159 := parse_metadata(xref_fixture('rfc7159.json')) or { panic(err) }

	cache := {
		7159: rfc7159
	}
	xr := build_xref(rfc8259, cache)

	assert xr.rfc.doc_id == 'RFC8259'
	// Obsoletes is fully resolved (cache has 7159).
	assert xr.obsoletes.len == 1
	assert xr.obsoletes[0].doc_id == 'RFC7159'
	assert xr.obsoletes[0].number == 7159
	assert xr.obsoletes[0].title.contains('JavaScript Object Notation')
	assert xr.obsoletes[0].pub_date == 'March 2014'

	// see_also references STD0090 — non-RFC, must be passed through with
	// number=0 and no resolved title.
	assert xr.see_also.len == 1
	assert xr.see_also[0].doc_id == 'STD0090'
	assert xr.see_also[0].number == 0
	assert xr.see_also[0].title == ''

	// The other categories are empty for RFC 8259.
	assert xr.obsoleted_by.len == 0
	assert xr.updates.len == 0
	assert xr.updated_by.len == 0
}

fn test_build_xref_keeps_bare_entry_when_metadata_missing() {
	// RFC 1149 lists RFC 2549 and RFC 6214 in updated_by; the fixture cache
	// is intentionally empty so neither resolves. Each entry must still be
	// returned with its raw doc_id so callers can render them.
	rfc1149 := parse_metadata(xref_fixture('rfc1149.json')) or { panic(err) }
	xr := build_xref(rfc1149, map[int]Rfc{})
	assert xr.updated_by.len == 2
	assert xr.updated_by[0].doc_id == 'RFC2549'
	assert xr.updated_by[0].number == 2549
	assert xr.updated_by[0].title == ''
	assert xr.updated_by[0].pub_date == ''
}
