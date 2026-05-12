module rfclib

import os
import rand

// HTTP tests rely exclusively on a pre-populated cache so they never hit the
// network: that keeps `v test ./rfclib` reproducible offline and on CI.

fn http_fixture(name string) string {
	path := os.join_path(@VMODROOT, 'rfclib', 'testdata', name)
	return os.read_file(path) or { panic('missing fixture ${path}: ${err}') }
}

fn make_test_client(offline bool) Client {
	root := os.join_path(os.vtmp_dir(), 'ietf-tools-http-test-${os.getpid()}-${rand.u64().hex()}')
	cache := new_cache_at(root) or { panic('cannot create test cache: ${err}') }
	return new_client_with(cache, offline)
}

fn test_fetch_returns_cached_body() {
	c := make_test_client(false)
	url := 'https://www.rfc-editor.org/rfc/rfc8259.txt'
	c.cache.put(url, 'cached body') or { panic(err) }
	got := c.fetch(url) or { panic('expected cached hit: ${err}') }
	assert got == 'cached body'
}

fn test_offline_mode_misses_return_err_offline() {
	c := make_test_client(true)
	if _ := c.fetch('https://www.rfc-editor.org/rfc/rfc99999.txt') {
		assert false, 'offline mode must not perform network calls'
	} else {
		// ErrOffline is distinct from ErrNotFound so the CLI can tell
		// "uncached in offline mode" apart from "upstream 404".
		assert err is ErrOffline
	}
}

fn test_metadata_decodes_typed_view() {
	c := make_test_client(false)
	body := http_fixture('rfc8259.json')
	c.cache.put(metadata_url(8259), body) or { panic(err) }
	rfc := c.metadata(8259) or { panic(err) }
	assert rfc.number() == 8259
	assert rfc.status == 'INTERNET STANDARD'
}

fn test_document_returns_cached_payload() {
	c := make_test_client(false)
	c.cache.put(format_url(8259, .text), 'RFC 8259 plaintext fixture') or { panic(err) }
	body := c.document(8259, .text) or { panic(err) }
	assert body.starts_with('RFC 8259')
}
