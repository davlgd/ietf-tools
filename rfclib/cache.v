module rfclib

import crypto.sha256
import os

// cache_subdir is the application directory created under the OS user-cache
// root. It is also the value displayed by `rfc --help` so users know where to
// look for and how to wipe the cache.
const cache_subdir = 'ietf-tools'

// Cache is a content-addressed on-disk cache used by the HTTP client to keep
// upstream IETF responses on the user's machine.
//
// Keys are deterministic: `sha256(url) -> hex` is used as the file name under
// `root`. Values are the raw response body. Misses return `none`; writes are
// atomic (write-then-rename) so a partial download never appears under the
// canonical key.
//
// Cache is safe for the single-process pattern of a CLI; concurrent writers
// (multiple `rfc` invocations racing on the same key) are correctly serialised
// by the rename, but no advisory locking is performed.
pub struct Cache {
pub:
	root string
}

// new_cache returns a Cache rooted at the OS user-cache directory, under a
// dedicated `ietf-tools` subdirectory. The directory is created on first call.
pub fn new_cache() !Cache {
	root := os.join_path(os.cache_dir(), cache_subdir)
	return new_cache_at(root)
}

// new_cache_at returns a Cache rooted at an explicit directory. Useful for
// tests and for users who want to override the default location. The
// directory is created on first call. Pointing at an existing
// non-directory path is refused upfront with a clear error rather than
// surfacing a confusing "failed to open <hash>.tmp" later.
pub fn new_cache_at(root string) !Cache {
	if os.exists(root) {
		if !os.is_dir(root) {
			return error('cache path ${root} exists but is not a directory')
		}
	} else {
		os.mkdir_all(root)!
	}
	return Cache{
		root: root
	}
}

// key returns the deterministic on-disk path used for `url`.
pub fn (c Cache) key(url string) string {
	digest := sha256.sum(url.bytes()).hex()
	return os.join_path(c.root, digest)
}

// get returns the cached body for `url`, or `none` if the entry is absent
// or unreadable.
pub fn (c Cache) get(url string) ?string {
	path := c.key(url)
	if !os.exists(path) {
		return none
	}
	return os.read_file(path) or { return none }
}

// put writes `body` to the cache under the key derived from `url`. The write
// is atomic: data is first written to a sibling temporary file, then renamed.
pub fn (c Cache) put(url string, body string) ! {
	path := c.key(url)
	tmp := '${path}.tmp'
	os.write_file(tmp, body)!
	os.mv(tmp, path)!
}

// has reports whether a cache entry exists for `url`.
pub fn (c Cache) has(url string) bool {
	return os.exists(c.key(url))
}

// clear removes every regular file under the cache root and returns how many
// entries were deleted. Subdirectories are left untouched.
pub fn (c Cache) clear() !int {
	if !os.exists(c.root) {
		return 0
	}
	entries := os.ls(c.root)!
	mut removed := 0
	for entry in entries {
		full := os.join_path(c.root, entry)
		if os.is_file(full) {
			os.rm(full)!
			removed++
		}
	}
	return removed
}
