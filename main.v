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
		description: 'Only use the local cache; do not perform network requests'
		global:      true
	})
	root.add_flag(Flag{
		flag:          .string
		name:          'cache-dir'
		description:   'Override the cache directory (default: OS user-cache + ietf-tools)'
		global:        true
		default_value: ['']
	})
	root.add_flag(Flag{
		flag:          .string
		name:          'format'
		abbrev:        'f'
		description:   'RFC rendering to fetch: text (default), html, pdf, xml'
		default_value: ['text']
	})

	mut info_cmd := Command{
		name:          'info'
		description:   'Show metadata for an RFC: status, dates, obsoletes, errata'
		usage:         '<rfc-number>'
		required_args: 1
		execute:       cmd_info
	}
	add_output_format_flag(mut info_cmd)
	root.add_command(info_cmd)

	mut search_cmd := Command{
		name:          'search'
		description:   'Search RFCs by title token(s) and optional status (IETF Datatracker)'
		usage:         '<token>...'
		required_args: 1
		execute:       cmd_search
	}
	search_cmd.add_flag(Flag{
		flag:          .string
		name:          'status'
		abbrev:        's'
		description:   'Filter by std_level slug (ps, std, bcp, inf, exp, hist, ds, unkn)'
		default_value: ['']
	})
	search_cmd.add_flag(Flag{
		flag:          .int
		name:          'limit'
		abbrev:        'n'
		description:   'Maximum number of hits to return (default 20)'
		default_value: ['20']
	})
	add_output_format_flag(mut search_cmd)
	search_cmd.add_flag(Flag{
		flag:        .bool
		name:        'refresh'
		description: 'Bypass the cache and re-query Datatracker'
	})
	root.add_command(search_cmd)

	mut track_cmd := Command{
		name:          'track'
		description:   'Show the IETF Datatracker state of an Internet-Draft'
		usage:         '<draft-name>'
		required_args: 1
		execute:       cmd_track
	}
	add_output_format_flag(mut track_cmd)
	track_cmd.add_flag(Flag{
		flag:        .bool
		name:        'refresh'
		description: 'Bypass the cache and re-fetch from Datatracker'
	})
	root.add_command(track_cmd)

	mut xref_cmd := Command{
		name:          'xref'
		description:   'Show the cross-reference graph of an RFC: obsoletes, updates, see also'
		usage:         '<rfc-number>'
		required_args: 1
		execute:       cmd_xref
	}
	add_output_format_flag(mut xref_cmd)
	root.add_command(xref_cmd)

	mut errata_cmd := Command{
		name:          'errata'
		description:   'List errata reported for an RFC (RFC Editor catalogue)'
		usage:         '<rfc-number>'
		required_args: 1
		execute:       cmd_errata
	}
	add_output_format_flag(mut errata_cmd)
	errata_cmd.add_flag(Flag{
		flag:        .bool
		name:        'refresh'
		description: 'Bypass the cache and redownload the errata catalogue'
	})
	root.add_command(errata_cmd)

	mut iana_cmd := Command{
		name:          'iana'
		description:   'Look up a code in an IANA registry (e.g. iana http-status-codes 404)'
		usage:         '<registry> <code>'
		required_args: 2
		execute:       cmd_iana
	}
	add_output_format_flag(mut iana_cmd)
	iana_cmd.add_flag(Flag{
		flag:        .bool
		name:        'refresh'
		description: 'Bypass the cache and redownload the registry'
	})
	root.add_command(iana_cmd)

	mut latest_cmd := Command{
		name:        'latest'
		description: 'List the most recently published RFCs (RFC Editor RSS feed)'
		execute:     cmd_latest
	}
	add_output_format_flag(mut latest_cmd)
	latest_cmd.add_flag(Flag{
		flag:        .bool
		name:        'refresh'
		description: 'Bypass the cache and fetch the feed directly from rfc-editor.org'
	})
	root.add_command(latest_cmd)

	mut bortzmeyer_cmd := Command{
		name:          'bortzmeyer'
		description:   "Open Stéphane Bortzmeyer's analysis for an RFC in your browser"
		usage:         '<rfc-number>'
		required_args: 1
		execute:       cmd_bortzmeyer
	}
	bortzmeyer_cmd.add_flag(Flag{
		flag:        .bool
		name:        'print'
		description: 'Only print the URL on stdout; do not launch a browser'
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
	root.parse(os.args)
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
	number := rfclib.parse_rfc_number(cmd.args[0])!
	format_str := cmd.flags.get_string('format') or { 'text' }
	format := rfclib.parse_format(format_str)!
	// Refuse to dump binary PDF straight into an interactive terminal: the
	// resulting noise scrambles the user's session. They can still pipe or
	// redirect, in which case stdout is not a TTY and the body flows.
	if format == .pdf && os.is_atty(1) != 0 {
		return error('refusing to write PDF to a terminal; redirect (e.g. > rfc${number}.pdf) or pipe to a viewer')
	}
	client := make_client(cmd)!
	body := client.fetch_format(number, format)!
	// Use `print` rather than `println`: keeps PDF/XML byte-exact and avoids a
	// stray newline on text/html where the RFC payload already ends in one.
	print(body)
}

fn cmd_info(cmd Command) ! {
	number := rfclib.parse_rfc_number(cmd.args[0])!
	format := cmd.flags.get_string('format') or { 'text' }
	client := make_client(cmd)!
	rfc := client.fetch_metadata(number)!
	match format.to_lower().trim_space() {
		'text' { print_info(rfc) }
		'json' { println(json2.encode(rfc, prettify: true)) }
		else { return error('unknown format: ${format} (expected: text, json)') }
	}
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
		return error('invalid draft name: ${cmd.args[0]} (expected fully-qualified, e.g. draft-ietf-quic-transport)')
	}
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	client := make_client(cmd)!
	draft := if refresh { client.refresh_draft(name)! } else { client.fetch_draft(name)! }
	state_index := client.fetch_states_index()!
	states := rfclib.resolve_states(draft, state_index)

	match format.to_lower().trim_space() {
		'text' {
			print_track(draft, states)
		}
		'json' {
			println(json2.encode({
				'draft':  json2.Any(json2.encode(draft))
				'states': json2.Any(json2.encode(states))
			},
				prettify: true
			))
		}
		else {
			return error('unknown format: ${format} (expected: text, json)')
		}
	}
}

fn print_track(d rfclib.Draft, states []rfclib.DraftState) {
	println('${d.name}-${d.rev}')
	if d.pages > 0 {
		println('  Pages:      ${d.pages}')
	}
	stream := d.stream_slug()
	if stream != '' {
		println('  Stream:     ${stream}')
	}
	intended := d.intended_slug()
	if intended != '' {
		println('  Intended:   ${intended}')
	}
	std_lvl := d.std_level_slug()
	if std_lvl != '' && std_lvl != intended {
		println('  Status:     ${std_lvl}')
	}
	if rfc := d.rfc_number {
		println('  Published:  RFC ${rfc}')
	}
	if expires := d.expires {
		if expires != '' {
			println('  Expires:    ${expires}')
		}
	}
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
	number := rfclib.parse_rfc_number(cmd.args[0])!
	format := cmd.flags.get_string('format') or { 'text' }
	client := make_client(cmd)!
	xr := client.fetch_xref(number)!

	match format.to_lower().trim_space() {
		'text' { print_xref(xr) }
		'json' { println(json2.encode(xr, prettify: true)) }
		else { return error('unknown format: ${format} (expected: text, json)') }
	}
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
	number := rfclib.parse_rfc_number(cmd.args[0])!
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	client := make_client(cmd)!
	errata := if refresh {
		client.refresh_errata_for(number)!
	} else {
		client.errata_for(number)!
	}

	match format.to_lower().trim_space() {
		'text' {
			if errata.len == 0 {
				eprintln('rfc: no errata reported for RFC ${number}')
				exit(1)
			}
			for e in errata {
				section := e.section or { '' }
				section_col := if section == '' { '—' } else { section }
				println('${e.errata_id:5}  ${e.errata_status_code:-25}  ${e.errata_type_code:-10}  ${e.submit_date}  ${section_col}  ${e.submitter_name}')
			}
		}
		'json' {
			println(json2.encode(errata, prettify: true))
		}
		else {
			return error('unknown format: ${format} (expected: text, json)')
		}
	}
}

fn cmd_search(cmd Command) ! {
	// Empty args are filtered upstream by `required_args: 1`, which makes
	// cli's parser exit before calling us; no defensive check needed here.
	status := rfclib.normalize_std_level(cmd.flags.get_string('status') or { '' })!
	limit := cmd.flags.get_int('limit') or { 20 }
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	query := rfclib.SearchQuery{
		title_tokens: cmd.args
		std_level:    status
		limit:        limit
	}
	client := make_client(cmd)!
	hits := if refresh { client.search_fresh(query)! } else { client.search(query)! }

	match format.to_lower().trim_space() {
		'text' {
			if hits.len == 0 {
				eprintln('rfc: no match')
				exit(1)
			}
			for h in hits {
				slug := h.std_level_short()
				date := h.updated_date()
				date_col := if date == '' { '          ' } else { date }
				slug_col := if slug == '' { '     ' } else { '${slug:5}' }
				println('${rfc_link(h.number)}  ${slug_col}  ${date_col}  ${h.title}')
			}
		}
		'json' {
			println(json2.encode(hits, prettify: true))
		}
		else {
			return error('unknown format: ${format} (expected: text, json)')
		}
	}
}

fn cmd_iana(cmd Command) ! {
	registry := cmd.args[0].trim_space()
	code := cmd.args[1].trim_space()
	if registry == '' || registry.contains(' ') || registry.contains('/') {
		return error('invalid registry slug: ${cmd.args[0]}')
	}
	if code == '' {
		return error('empty code')
	}
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	client := make_client(cmd)!
	rec := if refresh {
		client.refresh_iana(registry, code)!
	} else {
		client.fetch_iana(registry, code)!
	}

	match format.to_lower().trim_space() {
		'text' { print_iana(registry, rec) }
		'json' { println(json2.encode(rec, prettify: true)) }
		else { return error('unknown format: ${format} (expected: text, json)') }
	}
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
	client := make_client(cmd)!

	entries := if refresh {
		client.refresh_latest()!
	} else {
		client.fetch_latest()!
	}

	match format.to_lower().trim_space() {
		'text' {
			for e in entries {
				println('${rfc_link(e.number)}  ${e.title}')
			}
		}
		'json' {
			println(json2.encode(entries, prettify: true))
		}
		else {
			return error('unknown format: ${format} (expected: text, json)')
		}
	}
}

fn cmd_bortzmeyer(cmd Command) ! {
	number := rfclib.parse_rfc_number(cmd.args[0])!
	url := rfclib.bortzmeyer_url(number)
	print_only := cmd.flags.get_bool('print') or { false }

	client := make_client(cmd)!
	if !client.bortzmeyer_exists(number)! {
		eprintln('rfc: no Bortzmeyer article for RFC ${number} (${url})')
		exit(1)
	}
	if print_only {
		println(url)
		return
	}
	// Status message goes to stderr so stdout stays empty for callers piping
	// the command into a script.
	eprintln('Opening ${url}')
	os.open_uri(url)!
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
	cache := open_cache(cmd)!
	println(cache.root)
}

fn cmd_cache_clear(cmd Command) ! {
	cache := open_cache(cmd)!
	removed := cache.clear()!
	noun := if removed == 1 { 'entry' } else { 'entries' }
	println('removed ${removed} cache ${noun}')
}

fn print_info(r rfclib.Rfc) {
	println('${r.doc_id} — ${r.title.trim_space()}')
	println('  Authors:    ${r.authors.join(', ')}')
	if pub_date := r.pub_date {
		if pub_date != '' {
			println('  Date:       ${pub_date}')
		}
	}
	println('  Status:     ${r.status}')
	if page_count := r.page_count {
		if page_count > 0 {
			println('  Pages:      ${page_count}')
		}
	}
	if r.formats.len > 0 {
		println('  Formats:    ${r.formats.join(', ')}')
	}
	if r.keywords.len > 0 {
		println('  Keywords:   ${r.keywords.join(', ')}')
	}
	if r.obsoletes.len > 0 {
		println('  Obsoletes:  ${r.obsoletes.join(', ')}')
	}
	if r.obsoleted_by.len > 0 {
		println('  Obsoleted:  ${r.obsoleted_by.join(', ')}')
	}
	if r.updates.len > 0 {
		println('  Updates:    ${r.updates.join(', ')}')
	}
	if r.updated_by.len > 0 {
		println('  Updated by: ${r.updated_by.join(', ')}')
	}
	if r.see_also.len > 0 {
		println('  See also:   ${r.see_also.join(', ')}')
	}
	if doi := r.doi {
		if doi != '' {
			println('  DOI:        ${doi}')
		}
	}
	if errata := r.errata_url {
		if errata != '' {
			println('  Errata:     ${errata}')
		}
	}
	number := r.number()
	if number > 0 {
		println('  RFC Editor: ${rfclib.rfc_editor_info_url(number)}')
		println('  Tracker:    ${rfclib.datatracker_url(number)}')
	}
	if abstract := r.abstract {
		if abstract != '' {
			println('')
			println('Abstract:')
			for line in abstract.split_into_lines() {
				println('  ${line}')
			}
		}
	}
}
