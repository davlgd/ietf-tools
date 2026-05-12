// rfc is the entry-point CLI of the ietf-tools suite. It reads RFCs and
// inspects their metadata using the rfclib core, with persistent caching so
// repeat lookups never hit the network.
module main

import cli { Command, Flag }
import os
import rfclib
import x.json2

fn main() {
	mut root := Command{
		name:        'rfc'
		description: 'Read and inspect IETF RFCs from the command line'
		version:     rfclib.version
		usage:       '<rfc-number>'
		execute:     cmd_get
		posix_mode:  true
	}
	root.add_flag(Flag{
		flag:        .bool
		name:        'offline'
		description: 'Serve from the local cache; never hit the network'
		global:      true
	})
	root.add_flag(Flag{
		flag:          .string
		name:          'cache-dir'
		description:   'Cache directory (default: <os.cache_dir>/ietf-tools)'
		global:        true
		default_value: ['']
	})
	root.add_flag(Flag{
		flag:          .string
		name:          'format'
		abbrev:        'f'
		description:   'Document rendering: text (default), html, pdf, xml'
		default_value: ['text']
	})

	root.add_command(data_cmd(DataCmd{
		name:         'info'
		description:  'Show metadata for an RFC (status, dates, obsoletes)'
		usage:        '<rfc-number>'
		execute:      cmd_info
		refresh_desc: 'Bypass the cache and re-fetch the metadata'
	}))

	mut search_cmd := data_cmd(DataCmd{
		name:         'search'
		description:  'Search RFCs by title token(s) on the IETF Datatracker'
		usage:        '<token>...'
		execute:      cmd_search
		refresh_desc: 'Bypass the cache and re-query Datatracker'
	})
	search_cmd.add_flag(Flag{
		flag:          .string
		name:          'status'
		abbrev:        's'
		description:   'Filter by std_level: ps, std, bcp, inf, exp, hist, ds'
		default_value: ['']
	})
	search_cmd.add_flag(Flag{
		flag:          .int
		name:          'limit'
		abbrev:        'n'
		description:   'Maximum number of hits to return (default 20)'
		default_value: ['20']
	})
	root.add_command(search_cmd)

	root.add_command(data_cmd(DataCmd{
		name:         'track'
		description:  'Show the Datatracker state of an Internet-Draft'
		usage:        '<draft-name>'
		execute:      cmd_track
		refresh_desc: 'Bypass the cache and re-fetch from Datatracker'
	}))

	root.add_command(data_cmd(DataCmd{
		name:         'xref'
		description:  'Cross-reference graph: obsoletes, updates, see also'
		usage:        '<rfc-number>'
		execute:      cmd_xref
		refresh_desc: 'Bypass the cache and re-fetch every referenced RFC'
	}))

	root.add_command(data_cmd(DataCmd{
		name:         'errata'
		description:  'List errata reported for an RFC'
		usage:        '<rfc-number>'
		execute:      cmd_errata
		refresh_desc: 'Bypass the cache and redownload the catalogue'
	}))

	root.add_command(data_cmd(DataCmd{
		name:          'iana'
		description:   'Look up a code in an IANA registry'
		usage:         '<registry> <code>'
		required_args: 2
		execute:       cmd_iana
		refresh_desc:  'Bypass the cache and redownload the registry'
	}))

	root.add_command(data_cmd(DataCmd{
		name:          'latest'
		description:   'List the most recent RFCs (RFC Editor RSS feed)'
		required_args: 0
		execute:       cmd_latest
		refresh_desc:  'Bypass the cache and re-fetch the feed'
	}))

	mut bortzmeyer_cmd := Command{
		name:          'bortzmeyer'
		description:   "Open Stéphane Bortzmeyer's analysis in your browser"
		usage:         '<rfc-number>'
		required_args: 1
		execute:       cmd_bortzmeyer
	}
	bortzmeyer_cmd.add_flag(Flag{
		flag:        .bool
		name:        'print'
		description: 'Print the URL on stdout; do not launch a browser'
	})
	root.add_command(bortzmeyer_cmd)

	mut cache_cmd := Command{
		name:        'cache'
		description: 'Inspect or wipe the on-disk cache'
		execute:     cmd_cache
	}
	cache_cmd.add_command(Command{
		name:        'path'
		description: 'Print the cache directory'
		execute:     cmd_cache_path
	})
	cache_cmd.add_command(Command{
		name:        'clear'
		description: 'Remove every cached entry'
		execute:     cmd_cache_clear
	})
	root.add_command(cache_cmd)

	root.setup()
	root.parse(reorder_args(os.args))
}

// reorder_args rewrites argv so every flag token appears before any
// positional. V's `cli` module structurally stops parsing flags at the
// first non-flag arg, which means `rfc info 8259 -f json` silently drops
// `-f json` and falls back to the default format. Users do not expect
// that, and the silent failure mode is the worst kind (e.g. `rfc 8259
// -f pdf > out.pdf` would otherwise yield a text file masquerading as a
// PDF). Reordering preserves the user's intent regardless of where they
// place flags on the line.
//
// The function is intentionally schema-aware: only the small set of
// flags rfc exposes that *take a value* are known, so a boolean flag
// followed by a positional is not mistakenly consumed. Combined forms
// like `-fjson` and `--format=json` are passed through unchanged.
fn reorder_args(args []string) []string {
	if args.len <= 1 {
		return args
	}

	// Single pass: split every token after argv[0] into the flag block
	// (with their values) and the positional block. Combined forms like
	// `-fjson` and `--format=json` are self-contained so they pass through
	// without consuming a follow-up token.
	mut flags := []string{}
	mut positionals := []string{}
	mut i := 1
	for i < args.len {
		t := args[i]
		if t.starts_with('-') && t != '-' {
			flags << t
			if t in reorder_value_flags && i + 1 < args.len && !args[i + 1].starts_with('-') {
				flags << args[i + 1]
				i += 2
			} else {
				i += 1
			}
		} else {
			positionals << t
			i += 1
		}
	}

	// The subcommand (if any) is the first positional and must stay
	// directly after argv[0]; `cache <path|clear>` adds one more anchored
	// token because the sub-subcommand pair must not be interrupted by
	// reordered flags.
	mut prefix := [args[0]]
	mut tail := positionals.clone()
	if tail.len > 0 && tail[0] in reorder_subcommands {
		prefix << tail[0]
		if tail[0] == 'cache' && tail.len > 1 && tail[1] in reorder_cache_subs {
			prefix << tail[1]
			tail = tail[2..].clone()
		} else {
			tail = tail[1..].clone()
		}
	}

	mut out := prefix.clone()
	out << flags
	out << tail
	return out
}

const reorder_value_flags = ['-f', '--format', '--cache-dir', '-s', '--status', '-n', '--limit']
const reorder_subcommands = ['info', 'search', 'track', 'xref', 'errata', 'iana', 'latest',
	'bortzmeyer', 'cache', 'help', 'version', 'man']
const reorder_cache_subs = ['path', 'clear']

// die prints a friendly, prefixed error message on stderr and exits the
// process with status 1. It is the single channel for user-visible errors:
// using `return error(...)` from a subcommand callback routes through V's
// `cli` module which prefixes the message with the noisy "cli execution
// error:" banner, so subcommands prefer this helper instead.
@[noreturn]
fn die(msg string) {
	eprintln('rfc: ${msg}')
	exit(1)
}

// die_on_err formats an rfclib error into a self-contained message and
// exits. `not_found_label` is the human-friendly identifier the caller
// wants surfaced when the network layer's `ErrNotFound` carries a raw
// URL; rfclib lookups that already produced a descriptive resource
// label (e.g. iana's "<code> in <registry>") keep their own wording.
@[noreturn]
fn die_on_err(err IError, not_found_label string) {
	if err is rfclib.ErrNotFound {
		if err.resource.contains('://') {
			die('${not_found_label} not found')
		}
		die('${err.resource} not found')
	}
	if err is rfclib.ErrOffline {
		die('${not_found_label} is not cached (offline mode)')
	}
	// JSON/XML decode errors usually mean a poisoned cache entry. Point
	// the user at the most direct recovery instead of dumping the raw
	// parser message that "${not_found_label}" is then meant to explain.
	msg := err.msg()
	if msg.contains('Invalid json') || msg.contains('Invalid xml') {
		die('${not_found_label}: cached payload is corrupt (run with --refresh or `rfc cache clear`)')
	}
	die(msg)
}

// render dispatches a typed payload to either a text renderer or JSON,
// based on the user-supplied `format`. Centralising the dispatch keeps
// the text/json/error wording identical across every subcommand that
// honours `-f`.
fn render[T](format string, payload T, render_text fn (T)) {
	match format.to_lower().trim_space() {
		'text' { render_text(payload) }
		'json' { println(json2.encode(payload, prettify: true)) }
		else { die('unknown format: ${format} (expected: text, json)') }
	}
}

// DataCmd is the shared specification of every subcommand that exposes
// the `-f/--format` text/json toggle and the `--refresh` cache-bypass
// flag — every command except `bortzmeyer` and `cache`. Funnelling the
// boilerplate through `data_cmd` ensures the three knobs that matter
// (name, description, execute) stay close together at each call site.
struct DataCmd {
	name          string
	description   string
	usage         string
	required_args int            = 1
	execute       fn (Command) ! = unsafe { nil }
	refresh_desc  string
}

fn data_cmd(spec DataCmd) Command {
	mut cmd := Command{
		name:          spec.name
		description:   spec.description
		usage:         spec.usage
		required_args: spec.required_args
		execute:       spec.execute
	}
	add_output_format_flag(mut cmd)
	cmd.add_flag(Flag{
		flag:        .bool
		name:        'refresh'
		description: spec.refresh_desc
	})
	return cmd
}

// add_output_format_flag attaches the `-f/--format` flag (text|json) used by
// every subcommand that renders structured data — info, search, latest. The
// helper keeps the description and default value identical across commands
// so the user sees the same wording everywhere `-f` is offered.
fn add_output_format_flag(mut cmd Command) {
	cmd.add_flag(Flag{
		flag:          .string
		name:          'format'
		abbrev:        'f'
		description:   'Output format: text (default) or json'
		default_value: ['text']
	})
}

// make_client builds the rfclib Client honoured by every subcommand: it picks
// up the global `--cache-dir` and `--offline` flags so behaviour is uniform.
fn make_client(cmd Command) !rfclib.Client {
	cache := open_cache(cmd)!
	offline := cmd.flags.get_bool('offline') or { false }
	return rfclib.new_client_with(cache, offline)
}

// looks_like_rfc_number returns true when `input` plausibly denotes an
// RFC number — pure digits, or one of the textual prefixes accepted by
// `parse_rfc_number` (`RFC`, `rfc `, `rfc-`). The point is to tell apart
// "user typed an RFC reference but malformed it" from "user typed a word
// that was almost certainly a misspelled subcommand".
fn looks_like_rfc_number(input string) bool {
	s := input.trim_space()
	if s == '' {
		return false
	}
	if s[0] >= `0` && s[0] <= `9` {
		return true
	}
	return s.to_lower().starts_with('rfc')
}

fn open_cache(cmd Command) !rfclib.Cache {
	dir := cmd.flags.get_string('cache-dir') or { '' }
	if dir == '' {
		return rfclib.new_cache()!
	}
	return rfclib.new_cache_at(dir)!
}

fn cmd_get(cmd Command) ! {
	if cmd.args.len == 0 {
		cmd.execute_help()
		return
	}
	// The root command only fires when no subcommand matched, so an arg
	// that bears no resemblance to an RFC reference is almost certainly
	// a typo'd subcommand. Surface that explicitly rather than report a
	// confusing "invalid RFC number" for words that the user never
	// intended as a number.
	if !looks_like_rfc_number(cmd.args[0]) {
		die('unknown command: ${cmd.args[0]} (try `rfc --help`)')
	}
	number := rfclib.parse_rfc_number(cmd.args[0]) or { die(err.msg()) }
	format_str := cmd.flags.get_string('format') or { 'text' }
	format := rfclib.parse_format(format_str) or { die(err.msg()) }
	// Refuse to dump binary PDF straight into an interactive terminal: the
	// resulting noise scrambles the user's session. They can still pipe or
	// redirect, in which case stdout is not a TTY and the body flows.
	if format == .pdf && os.is_atty(1) != 0 {
		die('refusing to write PDF to a terminal; redirect (e.g. > rfc${number}.pdf) or pipe to a viewer')
	}
	client := make_client(cmd) or { die(err.msg()) }
	body := client.document(number, format) or { die_on_err(err, 'RFC ${number} (${format})') }
	// Use `print` rather than `println`: keeps PDF/XML byte-exact and avoids a
	// stray newline on text/html where the RFC payload already ends in one.
	print(body)
}

fn cmd_info(cmd Command) ! {
	number := rfclib.parse_rfc_number(cmd.args[0]) or { die(err.msg()) }
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }
	client := make_client(cmd) or { die(err.msg()) }
	rfc := client.metadata(number, refresh: refresh) or { die_on_err(err, 'RFC ${number}') }
	render(format, rfc, print_info)
}

// rfc_link renders an RFC number padded to five columns. When stdout is a
// TTY the digits are wrapped in an OSC 8 hyperlink pointing at the RFC
// Editor info page, so modern terminals turn the number into a click target.
// On non-TTY stdout (pipes, redirections, CI) the plain numeric form is
// emitted so machine consumers see clean text.
//
// The leading padding stays outside the hyperlink so terminals do not
// extend the click area to the surrounding whitespace.
fn rfc_link(number int) string {
	digits := number.str()
	width := 5
	pad := if digits.len < width { ' '.repeat(width - digits.len) } else { '' }
	if os.is_atty(1) == 0 {
		return '${pad}${digits}'
	}
	url := rfclib.rfc_editor_info_url(number)
	return '${pad}\x1b]8;;${url}\x1b\\${digits}\x1b]8;;\x1b\\'
}

fn cmd_track(cmd Command) ! {
	name := cmd.args[0].trim_space()
	if name == '' || name.contains(' ') {
		die('invalid draft name: ${cmd.args[0]} (expected fully-qualified, e.g. draft-ietf-quic-transport)')
	}
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	client := make_client(cmd) or { die(err.msg()) }
	draft := client.draft(name, refresh: refresh) or { die_on_err(err, 'draft ${name}') }
	state_index := client.states_index() or { die_on_err(err, 'Datatracker state catalogue') }
	states := rfclib.resolve_states(draft, state_index)

	render(format, TrackOutput{
		draft:  draft
		states: states
	}, fn (o TrackOutput) {
		print_track(o.draft, o.states)
	})
}

// TrackOutput is the typed JSON shape emitted by `rfc track -f json`.
// It bundles the draft document with its resolved state list so callers
// can decode both halves of the report in a single round-trip.
struct TrackOutput {
	draft  rfclib.Draft
	states []rfclib.DraftState
}

fn print_track(d rfclib.Draft, states []rfclib.DraftState) {
	println('${d.name}-${d.rev}')
	if d.pages > 0 {
		print_field('Pages', d.pages.str())
	}
	print_field('Stream', d.stream_slug())
	intended := d.intended_slug()
	print_field('Intended', intended)
	std_lvl := d.std_level_slug()
	if std_lvl != intended {
		print_field('Status', std_lvl)
	}
	if rfc := d.rfc_number {
		print_field('Published', 'RFC ${rfc}')
	}
	print_field('Expires', d.expires or { '' })
	if states.len > 0 {
		println('  States:')
		for s in states {
			println('    ${s.type_slug:-22}  ${s.label}')
		}
	}
	if d.abstract != '' {
		println('')
		println('Abstract:')
		for line in d.abstract.split_into_lines() {
			println('  ${line}')
		}
	}
}

fn cmd_xref(cmd Command) ! {
	number := rfclib.parse_rfc_number(cmd.args[0]) or { die(err.msg()) }
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }
	client := make_client(cmd) or { die(err.msg()) }
	xr := client.xref(number, refresh: refresh) or { die_on_err(err, 'RFC ${number}') }
	render(format, xr, print_xref)
}

fn print_xref(xr rfclib.Xref) {
	println('${xr.rfc.doc_id} — ${xr.rfc.title.trim_space()}')
	print_xref_section('Obsoletes', xr.obsoletes)
	print_xref_section('Obsoleted by', xr.obsoleted_by)
	print_xref_section('Updates', xr.updates)
	print_xref_section('Updated by', xr.updated_by)
	print_xref_section('See also', xr.see_also)
	if xr.obsoletes.len + xr.obsoleted_by.len + xr.updates.len + xr.updated_by.len + xr.see_also.len == 0 {
		println('  (no cross-references)')
	}
}

fn print_xref_section(label string, entries []rfclib.XrefEntry) {
	if entries.len == 0 {
		return
	}
	println('  ${label}:')
	for e in entries {
		if e.number > 0 {
			title := if e.title == '' { '(metadata unavailable)' } else { e.title }
			date := if e.pub_date == '' { '' } else { '  (${e.pub_date})' }
			println('    ${rfc_link(e.number)}  ${title}${date}')
		} else {
			println('    ${e.doc_id}')
		}
	}
}

fn cmd_errata(cmd Command) ! {
	number := rfclib.parse_rfc_number(cmd.args[0]) or { die(err.msg()) }
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	client := make_client(cmd) or { die(err.msg()) }
	errata := client.errata_for(number, refresh: refresh) or {
		die_on_err(err, 'errata for RFC ${number}')
	}
	if errata.len == 0 && format.to_lower().trim_space() == 'text' {
		die('no errata reported for RFC ${number}')
	}
	render(format, errata, print_errata)
}

fn print_errata(errata []rfclib.Erratum) {
	for e in errata {
		section := e.section or { '' }
		section_col := if section == '' { '—' } else { section }
		println('${e.errata_id:5}  ${e.errata_status_code:-25}  ${e.errata_type_code:-10}  ${e.submit_date}  ${section_col}  ${e.submitter_name}')
	}
}

fn cmd_search(cmd Command) ! {
	// Empty args are filtered upstream by `required_args: 1`, which makes
	// cli's parser exit before calling us; no defensive check needed here.
	status := rfclib.normalize_std_level(cmd.flags.get_string('status') or { '' }) or {
		die(err.msg())
	}
	limit := cmd.flags.get_int('limit') or { 20 }
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	tokens := cmd.args.map(it.trim_space()).filter(it != '')
	if tokens.len == 0 {
		die('search needs at least one non-empty token')
	}
	query := rfclib.SearchQuery{
		title_tokens: tokens
		std_level:    status
		limit:        limit
	}
	client := make_client(cmd) or { die(err.msg()) }
	hits := client.search(query, refresh: refresh) or { die_on_err(err, 'Datatracker search') }
	if hits.len == 0 && format.to_lower().trim_space() == 'text' {
		die('no match')
	}
	render(format, hits, print_search_hits)
}

fn print_search_hits(hits []rfclib.DatatrackerHit) {
	for h in hits {
		slug := h.std_level_short()
		date := h.updated_date()
		date_col := if date == '' { '          ' } else { date }
		slug_col := if slug == '' { '     ' } else { '${slug:5}' }
		println('${rfc_link(h.number)}  ${slug_col}  ${date_col}  ${h.title}')
	}
}

fn cmd_iana(cmd Command) ! {
	registry := cmd.args[0].trim_space()
	code := cmd.args[1].trim_space()
	if registry == '' || registry.contains(' ') || registry.contains('/') {
		die('invalid registry slug: ${cmd.args[0]}')
	}
	if code == '' {
		die('empty code')
	}
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	client := make_client(cmd) or { die(err.msg()) }
	rec := client.iana(registry, code, refresh: refresh) or {
		die_on_err(err, '${registry} registry')
	}
	render(format, rec, fn [registry] (r rfclib.IanaRecord) {
		print_iana(registry, r)
	})
}

fn print_iana(registry string, rec rfclib.IanaRecord) {
	println('${registry}:')
	mut width := 0
	for f in rec.fields {
		if f.name.len > width {
			width = f.name.len
		}
	}
	for f in rec.fields {
		pad := if f.name.len < width { ' '.repeat(width - f.name.len) } else { '' }
		println('  ${f.name}${pad}  ${f.value}')
	}
	if rec.refs.len > 0 {
		println('  References:')
		for r in rec.refs {
			label := if r.text == '' { r.data } else { r.text }
			println('    [${r.typ}] ${label}')
		}
	}
}

fn cmd_latest(cmd Command) ! {
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }
	client := make_client(cmd) or { die(err.msg()) }

	entries := client.latest(refresh: refresh) or { die_on_err(err, 'RFC Editor feed') }
	render(format, entries, print_latest)
}

fn print_latest(entries []rfclib.FeedEntry) {
	for e in entries {
		println('${rfc_link(e.number)}  ${e.title}')
	}
}

fn cmd_bortzmeyer(cmd Command) ! {
	number := rfclib.parse_rfc_number(cmd.args[0]) or { die(err.msg()) }
	url := rfclib.bortzmeyer_url(number)
	print_only := cmd.flags.get_bool('print') or { false }
	offline := cmd.flags.get_bool('offline') or { false }

	// In offline mode we cannot check the article exists (no HEAD), so
	// surface the URL verbatim and let the user decide. This is safer
	// than failing the entire command for a check the user disabled.
	if offline {
		if print_only {
			println(url)
			return
		}
		eprintln('Opening ${url} (existence not verified in offline mode)')
		os.open_uri(url) or { die(err.msg()) }
		return
	}

	client := make_client(cmd) or { die(err.msg()) }
	exists := client.bortzmeyer_exists(number) or { die(err.msg()) }
	if !exists {
		die('no Bortzmeyer article for RFC ${number} (${url})')
	}
	if print_only {
		println(url)
		return
	}
	// Status message goes to stderr so stdout stays empty for callers piping
	// the command into a script.
	eprintln('Opening ${url}')
	os.open_uri(url) or { die(err.msg()) }
}

// cmd_cache fires when the user runs `rfc cache` without a subcommand or
// with one the parser did not recognise. In both cases we print the local
// help so the available subcommands are visible; an unknown token is treated
// as a usage error and the process exits non-zero.
fn cmd_cache(cmd Command) ! {
	if cmd.args.len > 0 {
		eprintln('rfc: unknown cache subcommand: ${cmd.args[0]}')
		cmd.execute_help()
		exit(1)
	}
	cmd.execute_help()
}

fn cmd_cache_path(cmd Command) ! {
	cache := open_cache(cmd) or { die(err.msg()) }
	println(cache.root)
}

fn cmd_cache_clear(cmd Command) ! {
	cache := open_cache(cmd) or { die(err.msg()) }
	removed := cache.clear() or { die(err.msg()) }
	noun := if removed == 1 { 'entry' } else { 'entries' }
	println('removed ${removed} cache ${noun}')
}

fn print_info(r rfclib.Rfc) {
	println('${r.doc_id} — ${r.title.trim_space()}')
	print_field('Authors', r.authors.filter(it.trim_space() != '').join(', '))
	print_field('Date', r.pub_date or { '' })
	print_field('Status', r.status)
	if pages := r.page_count {
		if pages > 0 {
			print_field('Pages', pages.str())
		}
	}
	print_field('Formats', r.formats.filter(it.trim_space() != '').join(', '))
	print_list('Keywords', r.keywords)
	print_list('Obsoletes', r.obsoletes)
	print_list('Obsoleted', r.obsoleted_by)
	print_list('Updates', r.updates)
	print_list('Updated by', r.updated_by)
	print_list('See also', r.see_also)
	print_field('DOI', r.doi or { '' })
	print_field('Errata', r.errata_url or { '' })
	number := r.number()
	if number > 0 {
		print_field('RFC Editor', rfclib.rfc_editor_info_url(number))
		print_field('Tracker', rfclib.datatracker_url(number))
	}
	abstract := r.abstract or { '' }
	if abstract != '' {
		println('')
		println('Abstract:')
		for line in abstract.split_into_lines() {
			println('  ${line}')
		}
	}
}

// print_field prints "  <label>: <value>" with the label padded to a
// width wide enough for every label `print_info` emits. Empty values
// are silently skipped so callers don't need to guard each call.
fn print_field(label string, value string) {
	if value == '' {
		return
	}
	pad := if label.len < info_label_width {
		' '.repeat(info_label_width - label.len)
	} else {
		''
	}
	println('  ${label}:${pad}  ${value}')
}

// print_list is the list-valued companion of print_field: it joins the
// items with ", " and delegates to print_field, so the empty-list case
// is filtered uniformly.
fn print_list(label string, items []string) {
	print_field(label, items.join(', '))
}

// info_label_width tracks the longest label `print_info` emits
// ("Updated by", 10 chars). Bumping a label past this width is caught at
// review because the helper would no longer align it.
const info_label_width = 10
