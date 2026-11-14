/**
 * CueCard — script parsing
 *
 * A port of the iOS app's `TeleprompterParser`, `RichText` and `CueCards`, so
 * every app agrees on what a script says. `[smile]` is the form to write:
 * anything in brackets is a cue. `[cue smile]` and `[note smile]` are older
 * spellings and mean exactly the same thing, so scripts written before keep
 * working; importing, exporting or opening the app rewrites them to `[smile]`.
 * A bare `[cue]` is a cue that says "cue", the one Insert Cue writes for the
 * user to type over.
 *
 * A tag only counts once its closing bracket is there — `[smi` is still plain
 * text, so nothing changes under the user mid-word. Cues can't span lines for
 * the same reason: a stray `[` shouldn't swallow the paragraphs after it.
 *
 * Every cue is drawn in the one colour from Settings. An older `[cue:green …]`
 * still parses, but the colour name is ignored and dropped on the next import
 * or export.
 *
 * `[anchor]` marks a spot the teleprompter can jump to. `[separator]` ends one
 * card of a deck and starts the next; the teleprompter reads it as a line
 * break. `[image …]` is the phone app's picture, which this app reads past.
 *
 * Emphasis is written the way chat apps write it, `*bold*` and `_italic_`.
 */

/** Anything in brackets on one line, the text inside in group 1. */
const TAG_PATTERN = /\[([^\]\n]*)\]/g;

/** The tags that aren't cues. */
const isReservedTag = (inside) =>
  /^(?:anchor|separator)$/i.test(inside) || /^image[ \t]+[A-Za-z0-9-]+\.[A-Za-z0-9]+$/.test(inside);

const kindOf = (inside) => {
  if (/^anchor$/i.test(inside)) return 'anchor';
  if (/^separator$/i.test(inside)) return 'separator';
  if (/^image[ \t]+[A-Za-z0-9-]+\.[A-Za-z0-9]+$/.test(inside)) return 'image';
  return 'cue';
};

/**
 * The `cue ` / `note ` an older cue opens with, with its optional legacy
 * `:color`. A bare `cue` or `note` is the cue's text, not a prefix.
 */
const LEGACY_PREFIX = /^(?:cue|note)(?::[A-Za-z]+(?:[ \t]+|$)|[ \t]+)/;

/**
 * What a cue opens with, and closes with. Typing `[` writes both at once,
 * leaving the caret between them.
 */
export const CUE_TAG_PREFIX = '[';
export const CUE_TAG_SUFFIX = ']';

/** The tag typing `[` writes, for a cue that hasn't been written yet. */
export const EMPTY_CUE_TAG = CUE_TAG_PREFIX + CUE_TAG_SUFFIX;

/** What Insert Cue writes in a new cue, selected for the user to type over. */
export const PLACEHOLDER_CUE_TEXT = 'cue';

/** The tag that marks an anchor. */
export const ANCHOR_TAG = '[anchor]';

/** The tag that ends one card and starts the next. */
export const SEPARATOR_TAG = '[separator]';

/** Characters a card holds before the editor marks the rest as too long. */
export const CARD_CHARACTER_LIMIT = 280;

/** Build the tag for a cue. */
export function cueTag(text) {
  return CUE_TAG_PREFIX + (text || '').trim() + CUE_TAG_SUFFIX;
}

/**
 * Find every tag in the text, in order, each one saying what kind it is.
 *
 * An older `[cue …]` keeps its prefix as tag syntax, outside the cue's text.
 */
function tagMatches(text) {
  const pattern = new RegExp(TAG_PATTERN.source, 'g');
  const matches = [];

  for (const match of text.matchAll(pattern)) {
    const inside = match[1];
    const kind = kindOf(inside);
    const prefix = kind === 'cue' ? inside.match(LEGACY_PREFIX)?.[0].length ?? 0 : 0;

    matches.push({
      kind,
      isCue: kind === 'cue',
      index: match.index,
      length: match[0].length,
      contentIndex: match.index + 1 + prefix,
      content: inside.slice(prefix),
    });
  }

  return matches;
}

/** Find every cue tag in the text, in order — the tags the editor colours. */
export function cueMatches(text) {
  return tagMatches(text).filter((match) => match.isCue);
}

/** Every anchor tag in the text, in order. */
export function anchorMatches(text) {
  return tagMatches(text).filter((match) => match.kind === 'anchor');
}

/** Every tag that isn't a cue: anchors, separators and images. */
export function reservedMatches(text) {
  return tagMatches(text).filter((match) => !match.isCue);
}

/**
 * The cue tag the caret is sitting inside, if it is inside one.
 *
 * A caret resting against either bracket counts as outside: that's a spot a new
 * cue can legitimately go, and cues don't nest.
 */
export function cueTagContaining(location, text) {
  return cueMatches(text).find(
    (match) => match.index < location && location < match.index + match.length
  ) || null;
}

/**
 * Rewrite every cue tag into the canonical `[…]` spelling, and every card
 * separator into `[separator]`.
 *
 * Used at the file boundary, so a script that leaves the app carries the
 * current syntax and one that arrives is brought up to it.
 */
export function normalizingTags(text) {
  let result = text.replace(/\[separator\]/gi, SEPARATOR_TAG);

  // Back to front, so replacing a tag doesn't shift the ones still to come.
  for (const match of cueMatches(result).reverse()) {
    const tag = cueTag(match.content);
    // A cue that says "anchor" would come back as an anchor, so it keeps the
    // spelling it has.
    if (cueMatches(tag).length !== 1) continue;
    result = result.slice(0, match.index) + tag + result.slice(match.index + match.length);
  }

  return result;
}

/** Strip every tag out, leaving the words that are actually said. */
export function withoutTags(text) {
  let result = text;
  for (const match of tagMatches(text).reverse()) {
    result = result.slice(0, match.index) + result.slice(match.index + match.length);
  }
  return result;
}

/** The words a script says, tags and emphasis markers left out. */
export const plainText = (text) =>
  String(text || '')
    .split('\n')
    .map((line) => plainEmphasis(withoutTags(line)))
    .join('\n');

/** How many words are said, tags left out. */
export const wordCount = (text) => plainText(text).split(/\s+/).filter(Boolean).length;

/**
 * Split a single line into spoken text, cue and anchor runs. Images and
 * separators are dropped.
 *
 * Shared by the editor and the display so both render cues identically.
 */
export function segments(line) {
  const matches = tagMatches(line);
  if (matches.length === 0) return [{ type: 'text', value: line }];

  const result = [];
  let lastEnd = 0;

  for (const match of matches) {
    if (match.index > lastEnd) {
      const before = line.slice(lastEnd, match.index);
      if (before.trim()) result.push({ type: 'text', value: before.trim() });
    }
    if (match.isCue) result.push({ type: 'cue', value: match.content });
    else if (match.kind === 'anchor') result.push({ type: 'anchor' });
    lastEnd = match.index + match.length;
  }

  if (lastEnd < line.length) {
    const after = line.slice(lastEnd);
    if (after.trim()) result.push({ type: 'text', value: after.trim() });
  }

  return result;
}

// =============================================================================
// ANCHORS AND CARDS
// =============================================================================

/**
 * An anchor written on a line of its own moved onto the start of the line
 * after it, so it doesn't leave a blank line behind when reading. Anchors at
 * the very end mark nothing and are dropped.
 */
export function attachingAnchors(text) {
  return text
    .replace(/^[ \t]*((?:\[anchor\][ \t]*)+)\n+/gim, '$1')
    .replace(/(?:\s*\[anchor\])+\s*$/i, '');
}

/** Separators swapped for line breaks, for the teleprompter. */
export const removingSeparators = (text) => String(text || '').replace(/\[separator\]/gi, '\n');

/** The script as the teleprompter reads it. */
export const teleprompterText = (text) =>
  attachingAnchors(removingSeparators(String(text || '')).replace(/\r\n?/g, '\n').trim());

/** The stretches of text between separators, blank ones included. */
function cardRanges(text) {
  const ranges = [];
  let start = 0;
  for (const match of text.matchAll(/\[separator\]/gi)) {
    ranges.push([start, match.index]);
    start = match.index + match[0].length;
  }
  ranges.push([start, text.length]);
  return ranges;
}

/** The cards of a script, trimmed, with blank ones left out. */
export function cards(text) {
  const normalized = String(text || '').replace(/\r\n?/g, '\n');
  return cardRanges(normalized)
    .map(([start, end]) => normalized.slice(start, end).trim())
    .filter(Boolean);
}

/**
 * The cards as the editor shows them: blank ones kept, so a card just added
 * stays put, and the line breaks around each separator left out.
 */
export function editableCards(text) {
  const normalized = String(text || '').replace(/\r\n?/g, '\n');
  return cardRanges(normalized).map(([start, end]) => normalized.slice(start, end).replace(/^\n+|\n+$/g, ''));
}

/** The script for a deck, a separator on its own line between each card.
 *  A single blank card is no script at all. */
export function scriptForCards(list) {
  if (list.length === 1 && !list[0].trim()) return '';
  return list.join(`\n${SEPARATOR_TAG}\n`);
}

/** Whether a script is written as cards. */
export const hasSeparators = (text) => /\[separator\]/i.test(String(text || ''));

/**
 * Count what a card shows against the limit. Cue text counts, the `[` and `]`
 * around it don't, nor do emphasis markers, anchors or images, and neither
 * does blank space at either end.
 */
export function measureCard(card, limit = CARD_CHARACTER_LIMIT) {
  const skipped = new Set();
  const tags = tagMatches(card);
  for (const tag of tags) {
    const contentEnd = tag.contentIndex + tag.content.length;
    for (let i = tag.index; i < tag.index + tag.length; i += 1) {
      if (!tag.isCue || i < tag.contentIndex || i >= contentEnd) skipped.add(i);
    }
  }
  for (const range of markerRanges(card, cueMatches(card))) {
    for (let i = range.index; i < range.index + range.length; i += 1) skipped.add(i);
  }

  let count = 0;
  let solid = 0;
  let overflowAt = null;
  for (let i = 0; i < card.length; i += 1) {
    if (skipped.has(i)) continue;
    // A surrogate pair is one character.
    const code = card.charCodeAt(i);
    if (code >= 0xdc00 && code <= 0xdfff) continue;
    const blank = /\s/.test(card[i]);
    if (blank && count === 0) continue;
    count += 1;
    if (blank) continue;
    solid = count;
    if (count > limit && overflowAt === null) overflowAt = i;
  }
  return { length: solid, overflowAt };
}

// =============================================================================
// EMPHASIS
// =============================================================================

const isBlank = (ch) => /\s/.test(ch);
const isWordCharacter = (ch) => /[\p{L}\p{N}]/u.test(ch);

/**
 * Every emphasis in the text, closed ones and — at the end of a line — the
 * ones still waiting to be closed. `skipping` are ranges nothing is read
 * inside, such as the cue tags.
 *
 * Like cues, emphasis doesn't run across lines, and none is read inside a cue.
 * A marker only opens against a word and only closes after one, so `5 * 3`
 * and a `* ` bullet stay as they are; an `_` inside a word, as in
 * `snake_case`, is left alone too. Doubled markers read the same.
 */
export function emphases(text, skipping = []) {
  const result = [];
  let start = 0;
  for (;;) {
    let end = text.indexOf('\n', start);
    if (end === -1) end = text.length;
    result.push(...emphasesInLine(text, start, end, skipping));
    if (end >= text.length) break;
    start = end + 1;
  }
  return result;
}

function emphasesInLine(text, start, end, skipping) {
  const found = [];
  const stack = [];
  const isSkipped = (i) => skipping.some((r) => i >= r.index && i < r.index + r.length);
  const charAt = (i) => (i < start || i >= end || isSkipped(i) ? null : text[i]);
  const styleOf = (marker) => (marker === '*' ? 'bold' : 'italic');

  // What's still open where a cue or the line ends never closed; the editor
  // shows it styled so far, as it's being typed.
  const endOpeners = (at) => {
    for (const opener of stack) {
      const contentStart = opener.location + opener.length;
      found.push({
        style: styleOf(opener.marker),
        open: { index: opener.location, length: opener.length },
        close: null,
        content: { index: contentStart, length: at - contentStart },
      });
    }
    stack.length = 0;
  };

  let index = start;
  while (index < end) {
    if (isSkipped(index)) {
      endOpeners(index);
      index += 1;
      continue;
    }

    const marker = text[index];
    if (marker !== '*' && marker !== '_') {
      index += 1;
      continue;
    }

    let runEnd = index;
    while (runEnd < end && text[runEnd] === marker && !isSkipped(runEnd)) runEnd += 1;
    const runLength = runEnd - index;

    const previous = charAt(index - 1);
    const next = charAt(runEnd);
    let canOpen = next !== null && !isBlank(next);
    let canClose = previous !== null && !isBlank(previous);
    if (marker === '_') {
      canOpen = canOpen && !(previous !== null && isWordCharacter(previous));
      canClose = canClose && !(next !== null && isWordCharacter(next));
    }

    let used = 0;
    if (canClose) {
      // Inner markers close first, so `**_both_**` closes its `_` and then its `**`.
      while (used < runLength) {
        let openerIndex = -1;
        for (let k = stack.length - 1; k >= 0; k -= 1) {
          if (stack[k].marker === marker) {
            openerIndex = k;
            break;
          }
        }
        if (openerIndex < 0 || stack[openerIndex].length > runLength - used) break;
        const opener = stack[openerIndex];
        const open = { index: opener.location, length: opener.length };
        const close = { index: index + used, length: opener.length };
        found.push({
          style: styleOf(marker),
          open,
          close,
          content: { index: open.index + open.length, length: close.index - (open.index + open.length) },
        });
        // Anything opened inside it and never closed was never emphasis.
        stack.splice(openerIndex);
        used += opener.length;
      }
    }

    if (canOpen) {
      // `***` opens as `**` then `*`, each closed in turn.
      let location = index + used;
      while (location < runEnd) {
        const length = Math.min(2, runEnd - location);
        stack.push({ marker, location, length });
        location += length;
      }
    }

    index = runEnd;
  }

  endOpeners(end);
  return found;
}

/** Where the markers of closed emphasis are, which don't show once read. */
export function markerRanges(text, skipping = []) {
  return emphases(text, skipping).flatMap((emphasis) => (emphasis.close ? [emphasis.open, emphasis.close] : []));
}

/**
 * The text as it reads, closed markers taken out and each stretch carrying
 * its style: `[{ text, bold, italic }]`. A marker never closed is left in.
 */
export function styledRuns(text) {
  const closed = emphases(text).filter((emphasis) => emphasis.close);
  if (!closed.length) return text ? [{ text, bold: false, italic: false }] : [];

  const markers = new Set();
  for (const emphasis of closed) {
    for (const range of [emphasis.open, emphasis.close]) {
      for (let i = range.index; i < range.index + range.length; i += 1) markers.add(i);
    }
  }

  const runs = [];
  for (let i = 0; i < text.length; i += 1) {
    if (markers.has(i)) continue;
    let bold = false;
    let italic = false;
    for (const emphasis of closed) {
      if (i >= emphasis.content.index && i < emphasis.content.index + emphasis.content.length) {
        if (emphasis.style === 'bold') bold = true;
        else italic = true;
      }
    }
    const last = runs[runs.length - 1];
    if (last && last.bold === bold && last.italic === italic) last.text += text[i];
    else runs.push({ text: text[i], bold, italic });
  }
  return runs;
}

/** The text with its emphasis markers taken out. */
export const plainEmphasis = (text) => styledRuns(text).map((run) => run.text).join('');

// =============================================================================
// INSERTING
// =============================================================================

/**
 * The text to splice in for `tag` at `location`, spaced so it doesn't collide
 * with the words either side of it, and how far into that text the tag starts.
 */
function spacedInsertion(text, tag, location) {
  const previous = location > 0 ? text[location - 1] : '';
  const next = location < text.length ? text[location] : '';

  const isSpace = (ch) => ch !== '' && /\s/.test(ch);
  const leading = previous !== '' && !isSpace(previous) ? ' ' : '';
  const trailing = next !== '' && !isSpace(next) ? ' ' : '';

  return { text: leading + tag + trailing, tagOffset: leading.length };
}

/**
 * The text to splice in for an empty cue at `location`, spaced so it doesn't
 * collide with the words either side of it, and how far into that text the
 * caret belongs — between the brackets, ready for the cue to be typed.
 */
export function emptyCueInsertion(text, location) {
  const insertion = spacedInsertion(text, EMPTY_CUE_TAG, location);
  return { text: insertion.text, caretOffset: insertion.tagOffset + CUE_TAG_PREFIX.length };
}

/**
 * The text to splice in for a new cue at `location`, spaced the same way, and
 * where in that text its placeholder is — to be selected, ready for the cue to
 * be typed over it.
 */
export function newCueInsertion(text, location) {
  const insertion = spacedInsertion(text, cueTag(PLACEHOLDER_CUE_TEXT), location);
  const start = insertion.tagOffset + CUE_TAG_PREFIX.length;
  return { text: insertion.text, selectionStart: start, selectionEnd: start + PLACEHOLDER_CUE_TEXT.length };
}

/** The text to splice in for an anchor at `location`, and where the caret goes after it. */
export function anchorInsertion(text, location) {
  const insertion = spacedInsertion(text, ANCHOR_TAG, location);
  return { text: insertion.text, caretOffset: insertion.text.length };
}

/**
 * The range of an untouched `[]` the caret is sitting inside, if this
 * backspace is the one deleting its opening bracket. A cue with anything
 * written in it deletes a character at a time like ordinary text.
 */
export function emptyCueSurrounding(location, text) {
  const start = location - (CUE_TAG_PREFIX.length - 1);
  if (start < 0 || start + EMPTY_CUE_TAG.length > text.length) return null;
  if (text.slice(start, start + EMPTY_CUE_TAG.length) !== EMPTY_CUE_TAG) return null;
  return { index: start, length: EMPTY_CUE_TAG.length };
}

// =============================================================================
// SMALL THINGS
// =============================================================================

/** Format time as mm:ss, negative when the run has gone over. */
export function formatTime(seconds) {
  const negative = seconds < 0;
  const abs = Math.abs(seconds);
  const text = `${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`;
  return negative ? `-${text}` : text;
}

/** Time the way the timer button shows it: 1:00, 0:10. */
export const formatDuration = (seconds) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;

/**
 * The colours every delivery cue can be drawn in. The stored value has to stay
 * stable once shipped: renaming one resets that user's choice back to the
 * default.
 */
export const CUE_COLORS = ['pink', 'yellow', 'green', 'blue', 'purple', 'red'];

/** What cues are drawn in until the user picks something else. */
export const DEFAULT_CUE_COLOR = 'pink';

export const colorName = (name) => name[0].toUpperCase() + name.slice(1);

/** Titles are kept to this many characters, as on the phone. */
export const TITLE_LIMIT = 40;

export const limitedTitle = (title) => String(title || '').replace(/\s+/g, ' ').trim().slice(0, TITLE_LIMIT).trim();

/**
 * The name to suggest when a script is written out: the note's title, falling
 * back to the script's first line, falling back to something plain.
 */
export function suggestedFileName(title, content) {
  const sanitized = (name) => (name || '')
    .split(/[/\\:?%*|"<>]/)
    .join(' ')
    .trim();

  const candidates = [title, (content || '').split('\n')[0]];
  for (const candidate of candidates) {
    const name = sanitized(candidate);
    if (name) return name.slice(0, 60);
  }

  return 'Speech';
}

/** The title an imported script takes, which is the name the file already has. */
export function titleForFileName(fileName) {
  const base = (fileName || '').split(/[\\/]/).pop().replace(/\.[^.]+$/, '').trim();
  return limitedTitle(base) || 'Imported Script';
}
