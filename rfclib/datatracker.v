module rfclib

import net.urllib
import x.json2

// std_level_slug enumerates the slugs used by the IETF Datatracker for the
// "standardisation level" facet of an RFC. They are stable values the API
// accepts as filter parameters.
//
// Sourced from https://datatracker.ietf.org/api/v1/name/stdlevelname/
pub const std_level_slugs = ['bcp', 'ds', 'exp', 'hist', 'inf', 'std', 'ps', 'unkn']

// datatracker_page_size is the server-side page size we always request from
// Datatracker, independent of the user-facing `-n`. It is wide enough that
// the local AND-filter can find non-pivot tokens that appear deeper in the
// catalogue, yet stays well below the API's hard maximum of 1000.
//
// Caching benefits: every search for a given (pivot, status) maps to the
// exact same URL regardless of `-n`, so the on-disk cache is reused across
// invocations even when the user asks for different result counts.
const datatracker_page_size = 200

// SearchQuery encodes the filters a user can apply to `rfc search`. The
// struct is built directly from CLI flags so that the search logic is fully
// independent of the cli module.
pub struct SearchQuery {
pub:
	title_tokens []string // case-insensitive substrings, AND'd
	std_level    string   // slug, empty for no filter (see std_level_slugs)
	limit        int = 20
}

// DatatrackerHit is the projection of a Datatracker `document` object that
// `rfc search` actually surfaces. The field names mirror the upstream JSON
// where possible; `std_level` is kept as the raw URI emitted by the API and
// is converted to a slug on display.
pub struct DatatrackerHit {
pub:
	number    int @[json: 'rfc_number']
	title     string
	abstract  string
	pages     int
	std_level string @[json: 'std_level']
	time      string
}

// std_level_short returns the trailing slug of the std_level URI, e.g.
// "/api/v1/name/stdlevelname/ps/" -> "ps". Returns an empty string for
// documents that have no std_level set yet.
pub fn (h DatatrackerHit) std_level_short() string {
	if h.std_level == '' {
		return ''
	}
	trimmed := h.std_level.trim_string_right('/')
	idx := trimmed.last_index('/') or { return '' }
	return trimmed[idx + 1..]
}

struct DatatrackerMeta {
	total_count int
	limit       int
	offset      int
	next        ?string
}

struct DatatrackerResponse {
	meta    DatatrackerMeta
	objects []DatatrackerHit
}

// normalize_std_level turns a user-typed status string into the canonical
// Datatracker slug. Accepts both the slug itself ("ps") and a few common
// long forms ("proposed-standard"). Empty input is passed through (no
// filter applied).
pub fn normalize_std_level(input string) !string {
	cleaned := input.to_lower().trim_space().replace('_', '-')
	return match cleaned {
		'' { '' }
		'ps', 'proposed-standard', 'proposed' { 'ps' }
		'std', 'internet-standard', 'is' { 'std' }
		'bcp', 'best-current-practice' { 'bcp' }
		'inf', 'info', 'informational' { 'inf' }
		'exp', 'experimental' { 'exp' }
		'hist', 'historic' { 'hist' }
		'ds', 'draft-standard' { 'ds' }
		'unkn', 'unknown' { 'unkn' }
		else { error('unknown status: ${input} (expected one of: ps/proposed-standard, std/internet-standard, bcp, inf/informational, exp/experimental, hist/historic, ds/draft-standard, unkn/unknown)') }
	}
}

// build_search_url turns a SearchQuery into the canonical Datatracker URL
// used to fetch a wide page of results. The longest token is pushed
// server-side to narrow the result set; remaining tokens (and the
// case-insensitive AND semantics) are enforced locally by `search`. The
// server-side page size is fixed (`datatracker_page_size`) so that a given
// (pivot, status) combination always maps to the same URL — and the same
// cache entry — regardless of the user's `-n`.
pub fn build_search_url(q SearchQuery) !string {
	if q.title_tokens.len == 0 {
		return error('search requires at least one title token')
	}
	if q.limit <= 0 {
		return error('search limit must be positive')
	}
	pivot := longest_token(q.title_tokens)
	mut params := []string{}
	params << 'type=rfc'
	params << 'title__icontains=${urllib.query_escape(pivot)}'
	params << 'limit=${datatracker_page_size}'
	params << 'format=json'
	if q.std_level != '' {
		params << 'std_level=${urllib.query_escape(q.std_level)}'
	}
	return '${datatracker_base}/api/v1/doc/document/?${params.join('&')}'
}

// longest_token returns whichever token in `tokens` would, by virtue of
// being the longest, most narrow the server-side result set. Ties are
// broken by the first occurrence.
fn longest_token(tokens []string) string {
	mut pivot := tokens[0]
	for t in tokens[1..] {
		if t.len > pivot.len {
			pivot = t
		}
	}
	return pivot
}

// matches_all_tokens reports whether `title` contains every token in
// `tokens` as a case-insensitive substring.
fn matches_all_tokens(title string, tokens []string) bool {
	lowered := title.to_lower()
	for t in tokens {
		if !lowered.contains(t.to_lower()) {
			return false
		}
	}
	return true
}

// parse_search_response decodes a Datatracker search payload and returns the
// hit list, sorted by descending RFC number for a stable, newest-first
// presentation. Datatracker's REST endpoint does not let us order on
// `rfc_number` server-side, so the sort is unconditional and local.
pub fn parse_search_response(body string) ![]DatatrackerHit {
	resp := json2.decode[DatatrackerResponse](body)!
	mut hits := resp.objects.clone()
	hits.sort(a.number > b.number)
	return hits
}

// search runs `q` against the IETF Datatracker, post-filters the results so
// every title token matches (case-insensitive AND), and returns at most
// `q.limit` hits. The query URL goes through the normal cache.
pub fn (c Client) search(q SearchQuery) ![]DatatrackerHit {
	url := build_search_url(q)!
	body := c.fetch(url)!
	hits := parse_search_response(body)!
	return filter_and_limit(hits, q.title_tokens, q.limit)
}

// search_fresh is `search` with the cache bypassed; useful when a query was
// previously cached but the user wants the current state.
pub fn (c Client) search_fresh(q SearchQuery) ![]DatatrackerHit {
	url := build_search_url(q)!
	body := c.fetch_fresh(url)!
	hits := parse_search_response(body)!
	return filter_and_limit(hits, q.title_tokens, q.limit)
}

fn filter_and_limit(hits []DatatrackerHit, tokens []string, limit int) []DatatrackerHit {
	mut out := []DatatrackerHit{cap: hits.len}
	for h in hits {
		if matches_all_tokens(h.title, tokens) {
			out << h
		}
	}
	if out.len > limit {
		return out[..limit]
	}
	return out
}
