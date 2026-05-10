module rfclib

import os

fn errata_fixture() string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', 'errata_mini.json')
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn test_parse_errata_real_fixture() {
	all := parse_errata(errata_fixture()) or { panic(err) }
	// Mini fixture intentionally exercises every status code and every
	// nullable field (verifier_name, correct_text, notes, section,
	// orig_text, update_date).
	assert all.len == 10
	for e in all {
		assert e.errata_id != ''
		assert e.doc_id.starts_with('RFC')
		assert e.errata_status_code in ['Verified', 'Held for Document Update', 'Rejected',
			'Reported']
	}
}

fn test_parse_errata_decodes_null_fields() {
	all := parse_errata(errata_fixture()) or { panic(err) }
	// errata_id 208 has section=null, orig_text=null, correct_text=null
	// (and verifier_name=null).
	target := all.filter(it.errata_id == '208')
	assert target.len == 1
	e := target[0]
	if _ := e.section {
		assert false, 'section should be none for errata_id=208'
	}
	if _ := e.orig_text {
		assert false, 'orig_text should be none for errata_id=208'
	}
	if _ := e.correct_text {
		assert false, 'correct_text should be none for errata_id=208'
	}
	if _ := e.verifier_name {
		assert false, 'verifier_name should be none for errata_id=208'
	}
	// errata_id 5885 has update_date=null
	target_5885 := all.filter(it.errata_id == '5885')
	assert target_5885.len == 1
	if _ := target_5885[0].update_date {
		assert false, 'update_date should be none for errata_id=5885'
	}
}

fn test_filter_errata_isolates_one_rfc() {
	all := parse_errata(errata_fixture()) or { panic(err) }
	hits := filter_errata(all, 8259)
	assert hits.len == 1
	assert hits[0].errata_id == '5210'
	assert hits[0].number() == 8259
	assert hits[0].errata_status_code == 'Reported'
}

fn test_filter_errata_returns_empty_when_no_match() {
	all := parse_errata(errata_fixture()) or { panic(err) }
	assert filter_errata(all, 99999).len == 0
}

fn test_erratum_number_returns_zero_for_non_rfc() {
	e := Erratum{
		doc_id: 'BCP14'
	}
	assert e.number() == 0
}

fn test_parse_errata_rejects_garbage() {
	if _ := parse_errata('not json') {
		assert false, 'parser must reject non-json input'
	}
}
