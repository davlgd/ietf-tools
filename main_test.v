module main

fn test_reorder_args_pushes_flags_before_positional() {
	// `rfc 8259 -f pdf` → flags must precede the positional so the
	// underlying cli module actually parses them.
	out := reorder_args(['rfc', '8259', '-f', 'pdf'])
	assert out == ['rfc', '-f', 'pdf', '8259']
}

fn test_reorder_args_keeps_subcommand_anchored() {
	// The subcommand stays right after argv[0]; only the trailing
	// `-f json` token migrates ahead of `8259`.
	out := reorder_args(['rfc', 'info', '8259', '-f', 'json'])
	assert out == ['rfc', 'info', '-f', 'json', '8259']
}

fn test_reorder_args_handles_boolean_flag_after_positional() {
	// `--print` takes no value; the reorder must not pull `8259` along
	// with it.
	out := reorder_args(['rfc', 'bortzmeyer', '8259', '--print'])
	assert out == ['rfc', 'bortzmeyer', '--print', '8259']
}

fn test_reorder_args_preserves_combined_forms() {
	// `--format=json` is self-contained; the reorder must not split it.
	out := reorder_args(['rfc', 'info', '8259', '--format=json'])
	assert out == ['rfc', 'info', '--format=json', '8259']
}

fn test_reorder_args_keeps_cache_subsubcommand() {
	// `rfc cache path` and `rfc cache clear` must stay grouped because
	// `path`/`clear` are sub-subcommands, not positionals.
	assert reorder_args(['rfc', 'cache', 'path']) == ['rfc', 'cache', 'path']
	assert reorder_args(['rfc', 'cache', 'clear']) == ['rfc', 'cache', 'clear']
}

fn test_reorder_args_handles_multi_token_value_flag() {
	// `--cache-dir /tmp/x` is a flag-value pair: both tokens must move
	// together.
	out := reorder_args(['rfc', 'info', '8259', '--cache-dir', '/tmp/x'])
	assert out == ['rfc', 'info', '--cache-dir', '/tmp/x', '8259']
}

fn test_reorder_args_handles_search_with_multiple_tokens() {
	// Search accepts variadic positional tokens. Each one must survive.
	out := reorder_args(['rfc', 'search', 'json', 'transport', '-n', '5'])
	assert out == ['rfc', 'search', '-n', '5', 'json', 'transport']
}

fn test_reorder_args_no_op_when_already_ordered() {
	out := reorder_args(['rfc', '-f', 'pdf', '9000'])
	assert out == ['rfc', '-f', 'pdf', '9000']
}

fn test_reorder_args_handles_no_args() {
	assert reorder_args(['rfc']) == ['rfc']
}

fn test_looks_like_rfc_number_accepts_digit_and_prefixed_forms() {
	assert looks_like_rfc_number('8259')
	assert looks_like_rfc_number('rfc-8259')
	assert looks_like_rfc_number('RFC 8259')
	assert looks_like_rfc_number(' 8259')
}

fn test_looks_like_rfc_number_rejects_words() {
	// A typo'd subcommand must not slip past as a "candidate number".
	assert !looks_like_rfc_number('info')
	assert !looks_like_rfc_number('seach')
	assert !looks_like_rfc_number('')
	assert !looks_like_rfc_number('-1')
}

fn test_reorder_args_handles_flags_before_and_after_subcommand() {
	// Mixed placement: `--offline` precedes the subcommand, `--print`
	// follows the positional. Both must end up between the subcommand
	// name and the positional so the cli module attaches them to the
	// right command.
	out := reorder_args(['rfc', '--offline', 'bortzmeyer', '8259', '--print'])
	assert out == ['rfc', 'bortzmeyer', '--offline', '--print', '8259']
}

fn test_reorder_args_moves_global_flag_after_subcommand() {
	// Without this anchor, `rfc --offline info 8259` keeps `--offline`
	// at the root command, which can shadow a subcommand-local flag of
	// the same name.
	out := reorder_args(['rfc', '--offline', 'info', '8259'])
	assert out == ['rfc', 'info', '--offline', '8259']
}

fn test_reorder_args_does_not_swallow_lone_dash() {
	// A bare `-` is conventionally a stdin/stdout sentinel and must be
	// treated as a positional, not a flag.
	out := reorder_args(['rfc', 'info', '-'])
	assert out == ['rfc', 'info', '-']
}
