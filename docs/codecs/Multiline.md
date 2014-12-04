# Multiline Codec

The multiline codec processes multiple lines into a single event.

As long as lines match the specified `pattern` they are buffered. When a line is
encountered that does not match, an event is flushed as dictated by the `what`
option.

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](http://doctoc.herokuapp.com/)*

- [Example](#example)
- [Options](#options)
  - [`"max multiline bytes"`](#max-multiline-bytes)
  - [`"negate"`](#negate)
  - [`"pattern"`](#pattern)
  - [`"previous timeout"`](#previous-timeout)
  - [`"what"`](#what)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Example

	{
		"name": "multiline",
		"pattern": "^[0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} ",
		"negate": true,
		"what": "previous",
		"previous timeout": "30s"
	}

## Options

### `"max multiline bytes"`

*Number. Optional. Default: `spool max bytes`*

The maximum multiline length to process. If a multiline block exeeds this
length, it will be split across multiple events.

This setting can not be greater than the `spool max bytes` setting.

### `"negate"`

*Boolean. Optional. Default: false*

Negates `pattern` so that a match becomes a non-match and a non-match becomes a
match.

### `"pattern"`

*String. Required*

A regular expression to match against each line.

The syntax is detailed at https://code.google.com/p/re2/wiki/Syntax.

### `"previous timeout"`

*Duration. Optional. Default: 0. Ignored when "what" != "previous"*

When using `"previous"`, if `"previous timeout"` is not 0 any buffered lines
will be flushed as a single event if no more lines are received within the
specified time period.

### `"what"`

*String. Optional. Default: "previous"  
Available values: "previous", "next"*

* `"previous"`: When the line matches, it belongs in the same event as the
previous line. In other words, when matching stops treat the current line as the
start of the next event. Flush the previously buffered lines as a single event
and start a new buffer containing this line.

* `"next"`: When the line matches, it belongs in the same event as the next
line. In other words, when matching stops treat the current line as the end of
the current event. Flush the previously buffered lines along with this line as a
single event and start a new buffer.

A side effect of using `"previous"` is that an event will not be flushed until
the first line of the next event is encountered. The `"previous timeout"` option
offers a solution to this.
