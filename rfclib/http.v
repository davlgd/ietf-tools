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

// new_client returns a Client backed by the default OS cache location.
pub fn new_client() !Client {
	return Client{
		cache: new_cache()!
	}
}

// new_client_with returns a Client backed by an explicit Cache. Useful for
// tests and for users who supply `--cache-dir`.
pub fn new_client_with(cache Cache, offline bool) Client {
	return Client{
		cache:   cache
		offline: offline
	}
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
		return ErrNotFound{
			resource: url
		}
	}
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
