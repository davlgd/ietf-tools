module rfclib

import os

fn dt_fixture(name string) string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', name)
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn test_normalize_std_level_canonical_slugs() {
	pairs := {
		'ps':                    'ps'
		'PS':                    'ps'
		'proposed-standard':     'ps'
		'proposed':              'ps'
		'std':                   'std'
		'internet-standard':     'std'
		'IS':                    'std'
		'bcp':                   'bcp'
		'best-current-practice': 'bcp'
		'inf':                   'inf'
		'info':                  'inf'
		'informational':         'inf'
		'exp':                   'exp'
		'experimental':          'exp'
		'hist':                  'hist'
		'historic':              'hist'
		'unkn':                  'unkn'
		'unknown':               'unkn'
		'':                      ''
	}
	for input, expected in pairs {
		got := normalize_std_level(input) or { panic('rejected ${input}: ${err}') }
		assert got == expected, 'input=${input}'
	}
}

fn test_normalize_std_level_rejects_garbage() {
	for bad in ['draft', 'foo', 'live'] {
		if _ := normalize_std_level(bad) {
			assert false, 'accepted invalid status ${bad}'
		}
	}
}

fn test_build_search_url_picks_longest_token_and_encodes() {
	url := build_search_url(SearchQuery{
		title_tokens: ['tls', 'extension']
		limit:        20
	}) or { panic(err) }
	assert url.contains('title__icontains=extension'), url
	assert url.contains('type=rfc'), url
	// Server-side page size is fixed; the user-facing `-n` is enforced locally.
	assert url.contains('limit=${datatracker_page_size}'), url
	assert url.contains('format=json'), url
}

fn test_build_search_url_includes_status_when_set() {
	url := build_search_url(SearchQuery{
		title_tokens: ['tls']
		std_level:    'ps'
		limit:        10
	}) or { panic(err) }
	assert url.contains('std_level=ps'), url
}

fn test_build_search_url_url_encodes_token_with_space() {
	url := build_search_url(SearchQuery{
		title_tokens: ['json data']
		limit:        20
	}) or { panic(err) }
	// space is encoded as `+` (form-style) or `%20` depending on encoder.
	assert url.contains('title__icontains=json+data')
		|| url.contains('title__icontains=json%20data'), url
}

fn test_build_search_url_rejects_empty_tokens() {
	if _ := build_search_url(SearchQuery{
		title_tokens: []
		limit:        20
	})
	{
		assert false, 'accepted empty token list'
	}
}

fn test_build_search_url_rejects_zero_limit() {
	if _ := build_search_url(SearchQuery{
		title_tokens: ['tls']
		limit:        0
	})
	{
		assert false, 'accepted zero limit'
	}
}

fn test_parse_search_response_real_fixture() {
	hits := parse_search_response(dt_fixture('datatracker_search_json.json')) or { panic(err) }
	assert hits.len == 3
	// Sorted descending by rfc_number.
	for i in 1 .. hits.len {
		assert hits[i - 1].number >= hits[i].number, 'not sorted desc: ${hits.map(it.number)}'
	}
	for h in hits {
		assert h.number > 0
		assert h.title != ''
		assert h.std_level.starts_with('/api/v1/name/stdlevelname/'), h.std_level
	}
}

fn test_std_level_short_extracts_slug() {
	h := DatatrackerHit{
		number:    8259
		title:     'JSON'
		std_level: '/api/v1/name/stdlevelname/std/'
	}
	assert h.std_level_short() == 'std'
	empty := DatatrackerHit{}
	assert empty.std_level_short() == ''
}

fn test_updated_date_extracts_yyyy_mm_dd() {
	h := DatatrackerHit{
		number: 8259
		title:  'JSON'
		time:   '2020-01-21T08:32:41Z'
	}
	assert h.updated_date() == '2020-01-21'
	empty := DatatrackerHit{}
	assert empty.updated_date() == ''
	short := DatatrackerHit{
		time: '2020'
	}
	assert short.updated_date() == ''
}

fn test_filter_and_limit_enforces_and_semantics() {
	hits := [
		DatatrackerHit{
			number: 9000
			title:  'TLS 1.3 Extension'
		},
		DatatrackerHit{
			number: 8446
			title:  'TLS 1.3'
		},
		DatatrackerHit{
			number: 5246
			title:  'TLS Protocol'
		},
	]
	got := filter_and_limit(hits, ['tls', '1.3'], 20)
	assert got.len == 2
	assert got.map(it.number) == [9000, 8446]
}

fn test_filter_and_limit_truncates_to_limit() {
	hits := [
		DatatrackerHit{
			number: 1
			title:  'tls a'
		},
		DatatrackerHit{
			number: 2
			title:  'tls b'
		},
		DatatrackerHit{
			number: 3
			title:  'tls c'
		},
	]
	got := filter_and_limit(hits, ['tls'], 2)
	assert got.len == 2
}
