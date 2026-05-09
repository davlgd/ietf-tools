module rfclib

import os

fn feed_fixture() string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', 'rfc_feed.xml')
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn test_split_feed_title_extracts_number_and_text() {
	num, title :=
		split_feed_title('RFC 8259: The JavaScript Object Notation (JSON) Data Interchange Format')
	assert num == 8259
	assert title == 'The JavaScript Object Notation (JSON) Data Interchange Format'
}

fn test_split_feed_title_handles_long_titles() {
	num, title :=
		split_feed_title('RFC 9961: MPLS Segment Routing Point-to-Multipoint (P2MP) Policy Ping')
	assert num == 9961
	assert title == 'MPLS Segment Routing Point-to-Multipoint (P2MP) Policy Ping'
}

fn test_split_feed_title_falls_back_when_prefix_missing() {
	num, title := split_feed_title('Something off-spec')
	assert num == 0
	assert title == 'Something off-spec'
}

fn test_parse_feed_real_snapshot() {
	entries := parse_feed(feed_fixture()) or { panic(err) }
	// The captured fixture has at least 10 items; we don't pin to an exact
	// count because it will drift when the fixture is refreshed.
	assert entries.len >= 10
	for e in entries {
		assert e.number > 0, 'entry must have a parseable number: ${e}'
		assert e.title != '', 'entry must have a non-empty title: ${e}'
		assert e.link.starts_with('https://www.rfc-editor.org/info/rfc'), 'unexpected link: ${e.link}'
	}
}

fn test_parse_feed_first_item_matches_snapshot() {
	entries := parse_feed(feed_fixture()) or { panic(err) }
	first := entries[0]
	// The snapshot was captured with RFC 9961 at the top.
	assert first.number == 9961
	assert first.title == 'MPLS Segment Routing Point-to-Multipoint (P2MP) Policy Ping'
	assert first.link == 'https://www.rfc-editor.org/info/rfc9961'
	assert first.description.contains('Segment Routing')
}

fn test_parse_feed_rejects_garbage() {
	if _ := parse_feed('not xml at all') {
		assert false, 'parser must reject non-XML input'
	}
}
