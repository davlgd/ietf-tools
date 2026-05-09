module rfclib

import os
import rand

fn test_bortzmeyer_url_uses_number_as_path() {
	assert bortzmeyer_url(868) == 'https://www.bortzmeyer.org/868.html'
	assert bortzmeyer_url(8259) == 'https://www.bortzmeyer.org/8259.html'
	assert bortzmeyer_url(1149) == 'https://www.bortzmeyer.org/1149.html'
}

fn test_bortzmeyer_url_does_not_pad_zero() {
	// Bortzmeyer's URL scheme uses raw decimal numbers, no leading zeros even
	// for the small classics. Verifies we mirror that directly.
	assert bortzmeyer_url(1) == 'https://www.bortzmeyer.org/1.html'
	assert bortzmeyer_url(20) == 'https://www.bortzmeyer.org/20.html'
}

fn test_bortzmeyer_exists_refuses_offline() {
	root := os.join_path(os.vtmp_dir(), 'ietf-tools-bz-test-${os.getpid()}-${rand.u64().hex()}')
	cache := new_cache_at(root) or { panic(err) }
	c := new_client_with(cache, true) // offline
	if _ := c.bortzmeyer_exists(868) {
		assert false, 'offline mode must not perform HEAD requests'
	}
}
