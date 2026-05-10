module rfclib

import os

fn iana_fixture(name string) string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', name)
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn test_iana_url_uses_canonical_layout() {
	assert iana_url('http-status-codes') == 'https://www.iana.org/assignments/http-status-codes/http-status-codes.xml'
	assert iana_url('uri-schemes') == 'https://www.iana.org/assignments/uri-schemes/uri-schemes.xml'
}

fn test_find_iana_record_resolves_simple_code() {
	body := iana_fixture('iana_http_status_codes.xml')
	rec := find_iana_record(body, '404') or { panic('404 should be found') }
	// Must keep <value> and <description> as named fields.
	mut got_value := false
	mut got_description := false
	for f in rec.fields {
		if f.name == 'value' && f.value == '404' {
			got_value = true
		}
		if f.name == 'description' && f.value == 'Not Found' {
			got_description = true
		}
	}
	assert got_value, 'value=404 missing from fields'
	assert got_description, 'description=Not Found missing from fields'

	// Refs collect the <xref> children with their attributes preserved.
	assert rec.refs.len > 0
	mut got_rfc := false
	for r in rec.refs {
		if r.typ == 'rfc' && r.data.starts_with('rfc') {
			got_rfc = true
		}
	}
	assert got_rfc, 'expected at least one rfc xref'
}

fn test_find_iana_record_handles_numeric_range() {
	body := iana_fixture('iana_http_status_codes.xml')
	// 150 is unassigned; the fixture exposes it via a "<value>105-199</value>"
	// range record. The matcher must spot the containment.
	rec := find_iana_record(body, '150') or { panic('150 should match the unassigned range') }
	mut value := ''
	for f in rec.fields {
		if f.name == 'value' {
			value = f.value
		}
	}
	assert value.contains('-'), 'expected a range value, got ${value}'
}

fn test_find_iana_record_is_case_insensitive() {
	// http-status-codes is purely numeric so case folding is invisible there;
	// validate the helper directly to catch a future regression.
	assert matches_iana_field('Continue', 'continue')
	assert matches_iana_field('  Continue  ', 'continue')
	assert !matches_iana_field('Continue', 'continued')
}

fn test_find_iana_record_returns_none_for_unknown_code() {
	body := iana_fixture('iana_http_status_codes.xml')
	if _ := find_iana_record(body, 'nonexistent-code-zzz') {
		assert false, 'unknown code must not match'
	}
}

fn test_find_iana_record_returns_none_for_garbage_xml() {
	if _ := find_iana_record('not xml', '404') {
		assert false, 'parser must reject non-xml input'
	}
}

fn test_matches_numeric_range_boundaries() {
	assert matches_numeric_range('105-199', '105')
	assert matches_numeric_range('105-199', '150')
	assert matches_numeric_range('105-199', '199')
	assert !matches_numeric_range('105-199', '104')
	assert !matches_numeric_range('105-199', '200')
	// Non-range or non-numeric input must collapse to false rather than
	// raising — callers fall back on exact-match semantics.
	assert !matches_numeric_range('text', '5')
	assert !matches_numeric_range('a-b', '5')
	assert !matches_numeric_range('100-200', 'foo')
}
