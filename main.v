// rfc is the entry-point CLI of the ietf-tools suite. It reads RFCs and
// inspects their metadata using the rfclib core, with persistent caching so
// repeat lookups never hit the network.
module main

import cli { Command, Flag }
import os
import rfclib

fn main() {
	mut root := Command{
		name:        'rfc'
		description: 'Read and inspect IETF RFCs from the command line.'
		version:     rfclib.version
		usage:       '<rfc-number>'
		execute:     cmd_get
		posix_mode:  true
	}
	root.add_flag(Flag{
		flag:        .bool
		name:        'offline'
		description: 'Only use the local cache; do not perform network requests.'
		global:      true
	})
	root.add_flag(Flag{
		flag:          .string
		name:          'cache-dir'
		description:   'Override the cache directory (default: OS user-cache + ietf-tools).'
		global:        true
		default_value: ['']
	})

	root.add_command(Command{
		name:          'info'
		description:   'Show metadata for an RFC: status, dates, obsoletes, errata.'
		usage:         '<rfc-number>'
		required_args: 1
		execute:       cmd_info
	})

	mut cache_cmd := Command{
		name:        'cache'
		description: 'Inspect or wipe the on-disk cache.'
	}
	cache_cmd.add_command(Command{
		name:        'path'
		description: 'Print the cache directory.'
		execute:     cmd_cache_path
	})
	cache_cmd.add_command(Command{
		name:        'clear'
		description: 'Remove every cached entry.'
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
	client := make_client(cmd)!
	body := client.fetch_text(number)!
	println(body)
}

fn cmd_info(cmd Command) ! {
	number := rfclib.parse_rfc_number(cmd.args[0])!
	client := make_client(cmd)!
	rfc := client.fetch_metadata(number)!
	print_info(rfc)
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
	if r.errata_url != '' {
		println('  Errata:     ${r.errata_url}')
	}
	if r.abstract != '' {
		println('')
		println('Abstract:')
		for line in r.abstract.split_into_lines() {
			println('  ${line}')
		}
	}
}
