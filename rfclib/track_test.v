module rfclib

import os

fn track_fixture(name string) string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', name)
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn test_extract_slug_strips_trailing_slash() {
	assert extract_slug('/api/v1/name/streamname/ietf/') == 'ietf'
	assert extract_slug('/api/v1/name/stdlevelname/ps/') == 'ps'
	assert extract_slug('') == ''
	assert extract_slug('plain') == 'plain'
}

fn test_parse_draft_real_quic_fixture() {
	d := parse_draft(track_fixture('datatracker_draft_quic.json')) or { panic(err) }
	assert d.name == 'draft-ietf-quic-transport'
	assert d.rev == '34'
	assert d.pages == 151
	assert d.state_uris.len == 5
	assert d.intended_slug() == 'ps'
	assert d.std_level_slug() == 'ps'
	assert d.stream_slug() == 'ietf'
	if _ := d.rfc_number {
		assert false, 'rfc_number should be none for an unpublished draft'
	}
}

fn test_parse_states_index_and_resolve() {
	idx := parse_states_index(track_fixture('datatracker_states.json')) or { panic(err) }
	// The fixture covers every state type (~180 entries).
	assert idx.len > 100
	// Spot-check a known state used by QUIC's draft document.
	rfc_state := idx['/api/v1/doc/state/3/'] or { panic('state 3 missing') }
	assert rfc_state.label == 'RFC'
	assert rfc_state.type_slug == 'draft'
	assert rfc_state.slug == 'rfc'

	// Joining the QUIC draft against the index resolves all 5 states.
	d := parse_draft(track_fixture('datatracker_draft_quic.json')) or { panic(err) }
	resolved := resolve_states(d, idx)
	assert resolved.len == 5
	for s in resolved {
		assert s.label != '', 'state ${s.slug} has no label'
		assert s.type_slug != '', 'state ${s.slug} has no type_slug'
	}
}

fn test_resolve_states_skips_unknown_uris() {
	idx := map[string]DraftState{}
	d := Draft{
		name:       'draft-bogus'
		state_uris: ['/api/v1/doc/state/9999/']
	}
	assert resolve_states(d, idx).len == 0
}

fn test_parse_draft_rejects_garbage() {
	if _ := parse_draft('not json') {
		assert false, 'parser must reject non-json input'
	}
}
