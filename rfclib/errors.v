// Module rfclib provides reusable building blocks shared by every CLI in the
// ietf-tools suite: an HTTP client, an on-disk cache, and typed parsers for
// the public IETF data sources (RFC Editor, IETF Datatracker, IANA registries).
//
// The library is designed to be the single dependency every subcommand pulls
// in, so that behaviour around caching, User-Agent identification and error
// reporting stays consistent across the suite.
module rfclib

// version is the current rfclib release. CLIs should embed it in their
// `User-Agent` header so that IETF data sources can identify the client.
pub const version = '0.1.0'

// user_agent is the canonical identifier sent by every HTTP request issued
// through rfclib. It follows the convention used by other IETF clients
// (project name + version + contact URL).
pub const user_agent = 'ietf-tools/${version} (+https://github.com/davlgd/ietf-tools)'

// ErrInvalidNumber is returned when a value cannot be parsed as a positive RFC
// or draft revision number.
pub struct ErrInvalidNumber {
	Error
pub:
	value string
}

// msg renders ErrInvalidNumber for printing.
pub fn (e ErrInvalidNumber) msg() string {
	return 'invalid RFC number: ${e.value}'
}

// ErrNotFound is returned when an upstream resource (RFC, draft, registry)
// is not present at the IETF data source, typically signalled by HTTP 404.
pub struct ErrNotFound {
	Error
pub:
	resource string
}

// msg renders ErrNotFound for printing.
pub fn (e ErrNotFound) msg() string {
	return '${e.resource} not found'
}

// ErrUpstream wraps any non-success HTTP status returned by an IETF data
// source other than 404 (which surfaces as ErrNotFound).
pub struct ErrUpstream {
	Error
pub:
	url    string
	status int
}

// msg renders ErrUpstream for printing.
pub fn (e ErrUpstream) msg() string {
	return 'upstream ${e.url} returned HTTP ${e.status}'
}

// ErrOffline is returned when the client is in offline mode (`--offline`)
// and the requested URL is not in the cache. Distinguishing it from
// `ErrNotFound` matters at the CLI surface: the user should not see "RFC
// 7000 not found" when the document simply has not been fetched yet.
pub struct ErrOffline {
	Error
pub:
	url string
}

// msg renders ErrOffline for printing.
pub fn (e ErrOffline) msg() string {
	return 'offline mode and ${e.url} is not cached'
}
