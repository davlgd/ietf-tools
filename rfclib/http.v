module rfclib

import net.http
import time

// default_timeout is the read/write deadline applied to every HTTP request
// issued by the client. The IETF mirrors are sometimes slow to respond from
// outside the US; 30 s is generous enough for first-byte while still short
// enough that a frozen connection cannot strand a CLI.
const default_timeout = 30 * time.second

// Client is the rfclib HTTP fetcher: a thin layer above `net.http` that adds
// caching, a stable User-Agent, and uniform error handling.
//
// Every CLI in ietf-tools should obtain its bytes through Client rather than
// calling `net.http.get` directly, so behaviour stays consistent across the
// suite (cache location, identification of the client to upstream, retries).
pub struct Client {
pub:
	cache   Cache
	offline bool // when true, only cache hits succeed; misses return ErrNotFound
}

// new_client_with returns a Client backed by an explicit Cache. Useful for
// tests and for users who supply `--cache-dir`.
pub fn new_client_with(cache Cache, offline bool) Client {
	return Client{
		cache:   cache
		offline: offline
	}
}

// head performs a HEAD request and returns the response status code. It is
// intended for cheap existence checks (does an article exist? is a registry
// reachable?) and bypasses the cache entirely because HEAD has no body to
// store.
//
// HEAD requires reaching the network; in offline mode it returns an error
// rather than guessing from cache state.
pub fn (c Client) head(url string) !int {
	if c.offline {
		return error('cannot HEAD ${url} in offline mode')
	}
	resp := http.fetch(
		url:           url
		method:        .head
		user_agent:    user_agent
		read_timeout:  default_timeout
		write_timeout: default_timeout
	)!
	return resp.status_code
}

// fetch returns the body for `url` from the cache when available, otherwise
// fetches it over HTTPS and stores the response for next time.
//
// Errors:
//   - ErrNotFound when the upstream returns 404, or when the cache misses
//     while the client is in offline mode.
//   - ErrUpstream for any other non-2xx response.
//   - any underlying network error from `net.http`.
pub fn (c Client) fetch(url string) !string {
	if cached := c.cache.get(url) {
		return cached
	}
	if c.offline {
		return ErrOffline{
			url: url
		}
	}
	return c.network_get(url)!
}

// fetch_fresh always reaches the network and overwrites any cache entry for
// `url`. Useful for moving resources such as the RFC Editor feed where a
// cache hit may be too stale to be useful.
//
// In offline mode it returns an error rather than silently serving cache.
pub fn (c Client) fetch_fresh(url string) !string {
	if c.offline {
		return error('cannot refresh ${url} in offline mode')
	}
	return c.network_get(url)!
}

// network_get performs a GET, writes the response to the cache on success,
// and translates HTTP status codes into rfclib's typed error vocabulary.
fn (c Client) network_get(url string) !string {
	resp := http.fetch(
		url:           url
		method:        .get
		user_agent:    user_agent
		read_timeout:  default_timeout
		write_timeout: default_timeout
	)!
	match resp.status_code {
		200...299 {
			c.cache.put(url, resp.body)!
			return resp.body
		}
		404 {
			return ErrNotFound{
				resource: url
			}
		}
		else {
			return ErrUpstream{
				url:    url
				status: resp.status_code
			}
		}
	}
}
