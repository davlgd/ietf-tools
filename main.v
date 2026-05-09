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
	info_cmd.add_flag(Flag{
		flag:          .string
		name:          'format'
		abbrev:        'f'
		description:   'Output format: text (default) or json'
		default_value: ['text']
	})
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
	search_cmd.add_flag(Flag{
		flag:          .string
		name:          'format'
		abbrev:        'f'
		description:   'Output format: text (default) or json'
		default_value: ['text']
	})
	search_cmd.add_flag(Flag{
		flag:        .bool
		name:        'refresh'
		description: 'Bypass the cache and re-query Datatracker'
	})
	root.add_command(search_cmd)

	mut latest_cmd := Command{
		name:        'latest'
		description: 'List the most recently published RFCs (RFC Editor RSS feed)'
		execute:     cmd_latest
	}
	latest_cmd.add_flag(Flag{
		flag:          .string
		name:          'format'
		abbrev:        'f'
		description:   'Output format: text (default) or json'
		default_value: ['text']
	})
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

fn cmd_search(cmd Command) ! {
	if cmd.args.len == 0 {
		cmd.execute_help()
		return
	}
	status := rfclib.normalize_std_level(cmd.flags.get_string('status') or { '' })!
	limit := cmd.flags.get_int('limit') or { 20 }
	format := cmd.flags.get_string('format') or { 'text' }
	refresh := cmd.flags.get_bool('refresh') or { false }

	query := rfclib.SearchQuery{
		title_tokens: cmd.args.clone()
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
	if r.pub_date != '' {
		println('  Date:       ${r.pub_date}')
	}
	println('  Status:     ${r.status}')
	if r.page_count > 0 {
		println('  Pages:      ${r.page_count}')
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
	if r.doi != '' {
		println('  DOI:        ${r.doi}')
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
	if r.abstract != '' {
		println('')
		println('Abstract:')
		for line in r.abstract.split_into_lines() {
			println('  ${line}')
		}
	}
}
