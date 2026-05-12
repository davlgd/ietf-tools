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

fn test_parse_rfc_number_rejects_int_overflow() {
	// V's `string.int` clamps to `int_max` on overflow, so a 10+ digit
	// input that exceeds 2^31-1 would otherwise be silently truncated.
	// Reject those rather than serve a confusing "RFC <other> not found".
	overflowing := ['2147483648', '99999999999', 'RFC2147483648']
	for input in overflowing {
		if n := parse_rfc_number(input) {
			assert false, 'accepted overflowing input ${input} -> ${n}'
		}
	}
}

fn test_metadata_url() {
	assert metadata_url(8259) == 'https://www.rfc-editor.org/rfc/rfc8259.json'
	assert metadata_url(1149) == 'https://www.rfc-editor.org/rfc/rfc1149.json'
}

fn test_info_page_urls() {
	assert rfc_editor_info_url(8259) == 'https://www.rfc-editor.org/info/rfc8259'
	assert datatracker_url(8259) == 'https://datatracker.ietf.org/doc/rfc8259/'
	assert rfc_editor_info_url(1149) == 'https://www.rfc-editor.org/info/rfc1149'
	assert datatracker_url(1149) == 'https://datatracker.ietf.org/doc/rfc1149/'
}

fn test_format_extension_and_url() {
	assert Format.text.extension() == 'txt'
	assert Format.html.extension() == 'html'
	assert Format.pdf.extension() == 'pdf'
	assert Format.xml.extension() == 'xml'
	assert format_url(8259, .text) == 'https://www.rfc-editor.org/rfc/rfc8259.txt'
	assert format_url(8259, .html) == 'https://www.rfc-editor.org/rfc/rfc8259.html'
	assert format_url(9000, .pdf) == 'https://www.rfc-editor.org/rfc/rfc9000.pdf'
	assert format_url(9000, .xml) == 'https://www.rfc-editor.org/rfc/rfc9000.xml'
}

fn test_parse_format_accepts_common_spellings() {
	cases := {
		'text': Format.text
		'TEXT': Format.text
		'txt':  Format.text
		'html': Format.html
		'HTML': Format.html
		'htm':  Format.html
		'pdf':  Format.pdf
		'PDF':  Format.pdf
		'xml':  Format.xml
	}
	for input, expected in cases {
		got := parse_format(input) or { panic('rejected ${input}: ${err}') }
		assert got == expected, 'input=${input}'
	}
}

fn test_parse_format_rejects_unknown() {
	for bad in ['', '   ', 'doc', 'epub', 'asciidoc'] {
		if _ := parse_format(bad) {
			assert false, 'accepted invalid format ${bad}'
		}
	}
}

fn test_parse_metadata_internet_standard() {
	rfc := parse_metadata(fixture('rfc8259.json')) or { panic(err) }
	assert rfc.doc_id == 'RFC8259'
	assert rfc.number() == 8259
	assert rfc.title == 'The JavaScript Object Notation (JSON) Data Interchange Format'
	assert rfc.status == 'INTERNET STANDARD'
	page_count := rfc.page_count or { 0 }
	assert page_count == 16
	assert rfc.formats == ['ASCII', 'HTML']
	assert rfc.obsoletes == ['RFC7159']
	assert rfc.obsoleted_by.len == 0
	assert rfc.see_also == ['STD0090']
	errata := rfc.errata_url or { '' }
	assert errata == 'https://www.rfc-editor.org/errata/rfc8259'
	doi := rfc.doi or { '' }
	assert doi == '10.17487/RFC8259'
}

fn test_parse_metadata_with_null_errata_url() {
	// RFC 9767 has no errata reported, so the upstream JSON sets
	// `"errata_url": null`. Regression: this used to crash because the field
	// was decoded as a non-optional string.
	rfc := parse_metadata(fixture('rfc9767.json')) or { panic(err) }
	assert rfc.number() == 9767
	assert rfc.title == 'Grant Negotiation and Authorization Protocol Resource Server Connections'
	assert rfc.status == 'PROPOSED STANDARD'
	if _ := rfc.errata_url {
		assert false, 'errata_url should be none for RFC 9767'
	}
}

fn test_parse_metadata_not_issued_rfc() {
	// RFC 7000 is a "Not Issued" placeholder: draft, abstract, pub_date,
	// doi and page_count are all `null` upstream. Regression: this used
	// to crash with "Expected string, but got null" because the affected
	// fields were declared as plain strings.
	rfc := parse_metadata(fixture('rfc7000.json')) or { panic(err) }
	assert rfc.number() == 7000
	assert rfc.title == 'Not Issued'
	assert rfc.status == 'NOT ISSUED'
	if _ := rfc.page_count {
		assert false, 'page_count should be none for "Not Issued" RFC 7000'
	}
	if _ := rfc.draft {
		assert false, 'draft should be none for "Not Issued" RFC 7000'
	}
	if _ := rfc.abstract {
		assert false, 'abstract should be none for "Not Issued" RFC 7000'
	}
	if _ := rfc.pub_date {
		assert false, 'pub_date should be none for "Not Issued" RFC 7000'
	}
	if _ := rfc.doi {
		assert false, 'doi should be none for "Not Issued" RFC 7000'
	}
	if _ := rfc.errata_url {
		assert false, 'errata_url should be none for "Not Issued" RFC 7000'
	}
}

fn test_parse_metadata_obsoleted_doc() {
	rfc := parse_metadata(fixture('rfc7159.json')) or { panic(err) }
	assert rfc.number() == 7159
	assert rfc.obsoleted_by == ['RFC8259']
	assert rfc.obsoletes == ['RFC4627', 'RFC7158']
}

fn test_parse_metadata_experimental_with_keywords() {
	rfc := parse_metadata(fixture('rfc1149.json')) or { panic(err) }
	assert rfc.number() == 1149
	assert rfc.status == 'EXPERIMENTAL'
	assert rfc.keywords == ['avian', 'carrier', 'april', 'fools']
	assert rfc.updated_by == ['RFC2549', 'RFC6214']
	draft := rfc.draft or { '' }
	assert draft == ''
	assert rfc.authors == ['D. Waitzman']
}

fn test_parse_metadata_rejects_garbage() {
	if _ := parse_metadata('this is not json') {
		assert false, 'parser must reject non-json input'
	}
}
