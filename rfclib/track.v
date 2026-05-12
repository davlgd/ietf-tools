module rfclib

import x.json2

// Draft is the typed view of an Internet-Draft document as published by the
// IETF Datatracker at `/api/v1/doc/document/<name>/`. Only the fields the
// CLI actually surfaces are retained; the rest of the upstream payload is
// silently dropped by `x.json2`.
pub struct Draft {
pub:
	name               string
	rev                string // current revision (e.g. "34")
	pages              int
	abstract           string
	intended_std_level ?string @[json: 'intended_std_level']
	std_level          ?string @[json: 'std_level']
	stream             ?string
	expires            ?string
	rfc_number         ?int     @[json: 'rfc_number']
	state_uris         []string @[json: 'states']
}

// DraftState is the resolved (type, slug, label) triple that decorates each
// entry of `Draft.state_uris`. It is built by joining the draft's state
// list against the global state index fetched from
// `/api/v1/doc/state/?limit=500`.
pub struct DraftState {
pub:
	type_slug string
	slug      string
	label     string // human-readable state name (e.g. "I-D Exists", "Publication Requested")
}

// RawDraftState mirrors the upstream JSON shape of a single state object
// from `/api/v1/doc/state/`. Module-private (lowercase struct names are
// rejected by V's parser, so the type stays uppercase but the file does
// not re-export it). Callers see the simpler `DraftState` projection.
// The `name` JSON key is renamed to `state_name` so the V field does not
// shadow other identifiers.
struct RawDraftState {
	id           int
	slug         string
	state_name   string @[json: 'name']
	resource_uri string
	type_uri     string @[json: 'type']
}

struct RawStatesResponse {
	objects []RawDraftState
}

// parse_draft decodes a Datatracker `document` object into a typed Draft.
// URI-shaped fields (intended_std_level, std_level, stream) are kept as
// raw upstream values; callers use `Draft.intended_slug()` / similar
// helpers when they need just the trailing slug.
fn parse_draft(body string) !Draft {
	return json2.decode[Draft](body)!
}

// intended_slug returns the trailing slug of `intended_std_level`, or an
// empty string if the field is unset upstream.
pub fn (d Draft) intended_slug() string {
	return extract_slug(d.intended_std_level or { '' })
}

// std_level_slug returns the trailing slug of `std_level`.
pub fn (d Draft) std_level_slug() string {
	return extract_slug(d.std_level or { '' })
}

// stream_slug returns the trailing slug of `stream`.
pub fn (d Draft) stream_slug() string {
	return extract_slug(d.stream or { '' })
}

// extract_slug pulls the last non-empty path segment from a Datatracker
// resource URI such as "/api/v1/name/streamname/ietf/" -> "ietf". Empty
// or non-URI input collapses to "".
fn extract_slug(uri string) string {
	if uri == '' {
		return ''
	}
	trimmed := uri.trim_string_right('/')
	idx := trimmed.last_index('/') or { return trimmed }
	return trimmed[idx + 1..]
}

// parse_states_index decodes the global `/doc/state/` listing into a map
// keyed by `resource_uri`, suitable for joining a draft's `state_uris`
// against to obtain human-readable state names and types.
fn parse_states_index(body string) !map[string]DraftState {
	resp := json2.decode[RawStatesResponse](body)!
	mut idx := map[string]DraftState{}
	for raw in resp.objects {
		ds := DraftState{
			type_slug: extract_slug(raw.type_uri)
			slug:      raw.slug
			label:     raw.state_name
		}
		idx[raw.resource_uri] = ds
	}
	return idx
}

// resolve_states joins a draft's raw state URIs against the global index
// and returns the resolved DraftState entries in declaration order.
// Unknown URIs are silently skipped (the index is comprehensive and any
// unknown URI would likely indicate an upstream schema change).
pub fn resolve_states(draft Draft, index map[string]DraftState) []DraftState {
	mut out := []DraftState{cap: draft.state_uris.len}
	for uri in draft.state_uris {
		if s := index[uri] {
			out << s
		}
	}
	return out
}

// draft returns the Datatracker document for a draft `name`. Use a
// fully-qualified name such as `draft-ietf-quic-transport` (no revision
// suffix). The lookup is cache-first; pass `refresh: true` to bypass
// the cache.
pub fn (c Client) draft(name string, opts FetchOpts) !Draft {
	url := '${datatracker_base}/api/v1/doc/document/${name}/'
	body := c.fetch_with(url, opts)!
	return parse_draft(body)!
}

// states_index returns the global state catalogue used to resolve a
// draft's state URIs to human-readable names. The catalogue is small
// (~60 KB, ~180 entries) and rarely changes; a single cached copy serves
// every `track` invocation across the user's session.
pub fn (c Client) states_index(opts FetchOpts) !map[string]DraftState {
	url := '${datatracker_base}/api/v1/doc/state/?limit=500&format=json'
	body := c.fetch_with(url, opts)!
	return parse_states_index(body)!
}
