module rfclib

// bortzmeyer_base is Stéphane Bortzmeyer's blog, which publishes a per-RFC
// French-language analysis at `/<number>.html` for many — but not all —
// RFCs. The blog has been an unofficial reading companion to the RFC corpus
// for two decades. Module-private: callers go through `bortzmeyer_url`.
const bortzmeyer_base = 'https://www.bortzmeyer.org'

// bortzmeyer_url returns the canonical Bortzmeyer article URL for an RFC.
// The article may or may not exist; use `bortzmeyer_exists` to verify before
// opening it.
pub fn bortzmeyer_url(number int) string {
	return '${bortzmeyer_base}/${number}.html'
}

// bortzmeyer_exists reports whether a Bortzmeyer article exists for the given
// RFC number, by issuing a single HEAD request to the canonical URL.
//
// Returns:
//   - true on HTTP 200 (article exists)
//   - false on HTTP 404 (no article for this RFC)
//   - ErrUpstream for any other status code, so the caller can distinguish
//     "doesn't exist" from "blog is down".
pub fn (c Client) bortzmeyer_exists(number int) !bool {
	url := bortzmeyer_url(number)
	code := c.head(url)!
	match code {
		200 {
			return true
		}
		404 {
			return false
		}
		else {
			return ErrUpstream{
				url:    url
				status: code
			}
		}
	}
}
