module rfclib

import os

// fixture loads a real RFC metadata document captured from rfc-editor.org.
// Using upstream payloads as test vectors keeps the parser honest against
// schema drift instead of validating only synthetic shapes.
fn fixture(name string) string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', name)
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn test_parse_rfc_number_accepts_common_forms() {
	cases := {
		'8259':     8259
		'RFC8259':  8259
		'rfc8259':  8259
		'rfc 8259': 8259
		'RFC-8259': 8259
		'  8259  ': 8259
	}
	for input, expected in cases {
		got := parse_rfc_number(input) or { panic('rejected valid input ${input}: ${err}') }
		assert got == expected, 'input=${input}'
	}
}

fn test_parse_rfc_number_rejects_invalid() {
	bad := ['', '   ', 'rfc', '0', '-1', '8259abc', '08259', 'abc', 'rfc-0']
	for input in bad {
		if n := parse_rfc_number(input) {
			assert false, 'accepted invalid input ${input} -> ${n}'
		}
	}
}

fn test_metadata_url_and_text_url() {
	assert metadata_url(8259) == 'https://www.rfc-editor.org/rfc/rfc8259.json'
	assert text_url(8259) == 'https://www.rfc-editor.org/rfc/rfc8259.txt'
	assert metadata_url(1149) == 'https://www.rfc-editor.org/rfc/rfc1149.json'
}

fn test_info_page_urls() {
	assert rfc_editor_info_url(8259) == 'https://www.rfc-editor.org/info/rfc8259'
	assert datatracker_url(8259) == 'https://datatracker.ietf.org/doc/rfc8259/'
	assert rfc_editor_info_url(1149) == 'https://www.rfc-editor.org/info/rfc1149'
	assert datatracker_url(1149) == 'https://datatracker.ietf.org/doc/rfc1149/'
}

fn test_parse_metadata_internet_standard() {
	rfc := parse_metadata(fixture('rfc8259.json')) or { panic(err) }
	assert rfc.doc_id == 'RFC8259'
	assert rfc.number() == 8259
	assert rfc.title == 'The JavaScript Object Notation (JSON) Data Interchange Format'
	assert rfc.status == 'INTERNET STANDARD'
	assert rfc.page_count == 16
	assert rfc.formats == ['ASCII', 'HTML']
	assert rfc.obsoletes == ['RFC7159']
	assert rfc.obsoleted_by.len == 0
	assert rfc.is_obsolete() == false
	assert rfc.see_also == ['STD0090']
	assert rfc.errata_url == 'https://www.rfc-editor.org/errata/rfc8259'
	assert rfc.doi == '10.17487/RFC8259'
}

fn test_parse_metadata_obsoleted_doc() {
	rfc := parse_metadata(fixture('rfc7159.json')) or { panic(err) }
	assert rfc.number() == 7159
	assert rfc.is_obsolete() == true
	assert rfc.obsoleted_by == ['RFC8259']
	assert rfc.obsoletes == ['RFC4627', 'RFC7158']
}

fn test_parse_metadata_experimental_with_keywords() {
	rfc := parse_metadata(fixture('rfc1149.json')) or { panic(err) }
	assert rfc.number() == 1149
	assert rfc.status == 'EXPERIMENTAL'
	assert rfc.keywords == ['avian', 'carrier', 'april', 'fools']
	assert rfc.updated_by == ['RFC2549', 'RFC6214']
	assert rfc.draft == ''
	assert rfc.authors == ['D. Waitzman']
}

fn test_parse_metadata_rejects_garbage() {
	if _ := parse_metadata('this is not json') {
		assert false, 'parser must reject non-json input'
	}
}
