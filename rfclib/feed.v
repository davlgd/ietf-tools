module rfclib

import encoding.xml

// rfc_editor_feed_url is the canonical RSS 2.0 feed of recently published
// RFCs. The feed is small (a couple of KB), purpose-built for "what came
// out lately?" and updated whenever the RFC Editor announces a new RFC.
// Module-private: callers go through `Client.fetch_latest`.
const rfc_editor_feed_url = '${rfc_editor_base}/rfcrss.xml'

// FeedEntry mirrors the fields the RFC Editor RSS 2.0 feed publishes for
// each recently released RFC.
//
// Note: the feed does *not* expose per-item publication date, status,
// authors, or working group. Those fields require a separate metadata
// lookup (`rfc info <number>`) or the IETF Datatracker.
pub struct FeedEntry {
pub:
	number      int    // parsed from the "RFC NNNN: …" prefix in the title
	title       string // title text after the "RFC NNNN: " prefix
	link        string // info-page URL announced by the feed
	description string // long-form abstract as published in the feed
}

// parse_feed turns an RSS 2.0 feed body into a list of FeedEntry values, in
// the order published by the feed (most recent first).
pub fn parse_feed(body string) ![]FeedEntry {
	doc := xml.XMLDocument.from_string(body)!
	items := doc.root.get_elements_by_tag('item')
	mut out := []FeedEntry{cap: items.len}
	for item in items {
		title := first_text_in(item, 'title')
		number, stripped := split_feed_title(title)
		out << FeedEntry{
			number:      number
			title:       stripped
			link:        first_text_in(item, 'link')
			description: first_text_in(item, 'description')
		}
	}
	return out
}

// first_text_in returns the concatenated text of the first child element
// named `tag` under `node`. Both raw text children and CDATA sections are
// included so the function works regardless of how the upstream encodes
// special characters.
fn first_text_in(node xml.XMLNode, tag string) string {
	matches := node.get_elements_by_tag(tag)
	if matches.len == 0 {
		return ''
	}
	mut buf := ''
	for child in matches[0].children {
		match child {
			string { buf += child }
			xml.XMLCData { buf += child.text }
			else {}
		}
	}
	return buf
}

// split_feed_title takes a feed `<title>` like "RFC 8259: The JavaScript
// Object Notation (JSON) Data Interchange Format" and returns
// (8259, "The JavaScript Object Notation (JSON) Data Interchange Format").
// When the prefix is missing or the digits between "RFC " and ": " are not
// purely numeric, it returns (0, original) so that callers can still display
// unparsable entries without truncating the title.
fn split_feed_title(s string) (int, string) {
	if !s.starts_with('RFC ') {
		return 0, s
	}
	rest := s[4..]
	colon := rest.index(': ') or { return 0, s }
	digits := rest[..colon]
	if digits.len == 0 {
		return 0, s
	}
	for c in digits {
		if c < `0` || c > `9` {
			return 0, s
		}
	}
	return digits.int(), rest[colon + 2..]
}

// fetch_latest returns the parsed feed using the cache; subsequent calls
// within the same session will be served from disk.
pub fn (c Client) fetch_latest() ![]FeedEntry {
	body := c.fetch(rfc_editor_feed_url)!
	return parse_feed(body)!
}

// refresh_latest forces a network round-trip and overwrites the cached feed
// copy. Use this when you specifically want the freshest view (the feed is
// the only resource in rfclib that a stale cache can mislead).
pub fn (c Client) refresh_latest() ![]FeedEntry {
	body := c.fetch_fresh(rfc_editor_feed_url)!
	return parse_feed(body)!
}
