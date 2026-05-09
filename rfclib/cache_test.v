module rfclib

import os
import rand

fn make_temp_cache() Cache {
	root := os.join_path(os.vtmp_dir(), 'ietf-tools-test-${os.getpid()}-${rand.u64().hex()}')
	return new_cache_at(root) or { panic('cannot create test cache: ${err}') }
}

fn test_key_is_deterministic() {
	c := make_temp_cache()
	a := c.key('https://www.rfc-editor.org/rfc/rfc8259.txt')
	b := c.key('https://www.rfc-editor.org/rfc/rfc8259.txt')
	assert a == b
	assert a.starts_with(c.root)
}

fn test_key_differs_per_url() {
	c := make_temp_cache()
	a := c.key('https://www.rfc-editor.org/rfc/rfc8259.txt')
	b := c.key('https://www.rfc-editor.org/rfc/rfc7159.txt')
	assert a != b
}

fn test_get_returns_none_on_miss() {
	c := make_temp_cache()
	assert c.has('https://example.invalid/x') == false
	if _ := c.get('https://example.invalid/x') {
		assert false, 'cache miss should return none'
	}
}

fn test_put_then_get_roundtrip() {
	c := make_temp_cache()
	url := 'https://www.rfc-editor.org/rfc/rfc8259.txt'
	body := 'hello rfc body'
	c.put(url, body) or { panic(err) }
	assert c.has(url)
	got := c.get(url) or { panic('expected hit') }
	assert got == body
}

fn test_put_is_atomic_no_tmp_left() {
	c := make_temp_cache()
	c.put('https://x/y', 'data') or { panic(err) }
	entries := os.ls(c.root) or { panic(err) }
	for e in entries {
		assert !e.ends_with('.tmp'), 'temp file leaked: ${e}'
	}
}

fn test_put_overwrites_existing() {
	c := make_temp_cache()
	url := 'https://x/y'
	c.put(url, 'first') or { panic(err) }
	c.put(url, 'second') or { panic(err) }
	got := c.get(url) or { panic('expected hit') }
	assert got == 'second'
}

fn test_clear_removes_all_files() {
	c := make_temp_cache()
	c.put('https://a/1', 'a') or { panic(err) }
	c.put('https://b/2', 'b') or { panic(err) }
	c.put('https://c/3', 'c') or { panic(err) }
	removed := c.clear() or { panic(err) }
	assert removed == 3
	entries := os.ls(c.root) or { panic(err) }
	assert entries.len == 0
}
