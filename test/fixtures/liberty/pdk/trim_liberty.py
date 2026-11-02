#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Drop the timing and power tables from a Liberty file, keeping the rest.

    python3 -I trim_liberty.py IN.lib OUT.lib.gz

Removes every `timing`, `internal_power` and `leakage_power` group, wherever
it is nested, and nothing else: cells, pins with their directions,
functions, `three_state` and `clock` attributes, `pg_pin` groups, `ff`,
`latch` and `statetable` groups, areas, comments and the library header are
copied byte for byte. Strings and comments are honoured, so a brace or a
group name inside either is never mistaken for structure.

OUT is gzip-compressed (with no name or time stamp in the header, so the
same input gives the same bytes) when its name ends in `.gz`.
"""

import gzip
import re
import sys

DROP = {'timing', 'internal_power', 'leakage_power'}

_COMMENT = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)
_HEADER = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(')


def _skip_string(text, i):
    """Index just past the string whose opening quote is at [i]."""
    i += 1
    while True:
        c = text[i]
        if c == '\\':
            i += 2
        elif c == '"':
            return i + 1
        else:
            i += 1


def _skip_comment(text, i):
    """Index just past the comment starting at [i], or [i] if none does."""
    if text.startswith('/*', i):
        return text.index('*/', i + 2) + 2
    if text.startswith('//', i):
        end = text.find('\n', i)
        return len(text) if end < 0 else end
    return i


def _matching_brace(text, i):
    """Index just past the `}` closing the `{` at [i]."""
    depth = 0
    while True:
        c = text[i]
        if c == '"':
            i = _skip_string(text, i)
            continue
        after = _skip_comment(text, i)
        if after != i:
            i = after
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1


def trim(text):
    out = []
    copied = 0
    statement = 0
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == '"':
            i = _skip_string(text, i)
            continue
        after = _skip_comment(text, i)
        if after != i:
            i = after
            continue
        if c in ';}':
            i += 1
            statement = i
            continue
        if c == '{':
            header = _COMMENT.sub(' ', text[statement:i])
            match = _HEADER.match(header)
            if match and match.group(1) in DROP:
                end = _matching_brace(text, i)
                # Cut from the group's name (from the start of its line when
                # only blanks precede it there) through the end of its
                # closing line when nothing follows the brace on it.
                head = text[statement:i]
                start = statement + len(head) - len(head.lstrip())
                line_start = text.rfind('\n', 0, start) + 1
                if not text[line_start:start].strip():
                    start = max(line_start, copied)
                stop = end
                rest = text.find('\n', end)
                if rest >= 0 and not text[end:rest].strip():
                    stop = rest + 1
                out.append(text[copied:start])
                copied = stop
                i = stop
                statement = stop
                continue
            i += 1
            statement = i
            continue
        i += 1
    out.append(text[copied:])
    return ''.join(out)


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    source, target = argv[1], argv[2]
    opener = gzip.open if source.endswith('.gz') else open
    with opener(source, 'rt', encoding='utf-8', errors='surrogateescape',
                newline='') as f:
        text = f.read()
    trimmed = trim(text).encode('utf-8', errors='surrogateescape')
    if target.endswith('.gz'):
        with open(target, 'wb') as raw:
            with gzip.GzipFile(filename='', mode='wb', fileobj=raw,
                               compresslevel=9, mtime=0) as f:
                f.write(trimmed)
    else:
        with open(target, 'wb') as f:
            f.write(trimmed)


if __name__ == '__main__':
    main(sys.argv)
