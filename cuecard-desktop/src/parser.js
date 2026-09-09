/**
 * CueCard — script parsing
 *
 * A port of the iOS app's `TeleprompterParser`, so both apps agree on what a
 * script says. `[cue smile]` is the form to write. `[note smile]` is the older
 * spelling and means exactly the same thing, so scripts written before the
 * rename keep working; importing or exporting rewrites them to `[cue …]`.
 *
 * A tag only counts once its closing bracket is there — `[cue smi` is still
 * plain text, so nothing changes under the user mid-word. Cues can't span lines
 * for the same reason: a stray `[` shouldn't swallow the paragraphs after it.
 *
 * Every cue is drawn in the one colour from Settings. An older `[cue:green …]`
 * still parses, but the colour name is ignored and dropped on the next import
 * or export.
 */

/** `[cue]` / `[note]`, an optional legacy `:color`, then the cue text. */
export const CUE_PATTERN = /\[(?:cue|note)(?::[A-Za-z]+)?(?:[ \t]+([^\]\n]*))?\]/g;

/**
 * What an empty cue opens with, and closes with. Typing `[` writes both at
 * once, leaving the caret between them.
 */
export const CUE_TAG_PREFIX = '[cue ';
export const CUE_TAG_SUFFIX = ']';

/** The tag inserted for a cue that hasn't been written yet. */
export const EMPTY_CUE_TAG = CUE_TAG_PREFIX + CUE_TAG_SUFFIX;

/** Build the tag for a cue. */
export function cueTag(text) {
  return CUE_TAG_PREFIX + (text || '').trim() + CUE_TAG_SUFFIX;
}

/**
 * Find every cue tag in the text, in order.
 *
 * `[cue]` carries no text group at all; treat it as an empty cue sitting just
 * inside the closing bracket.
 */
export function cueMatches(text) {
  const pattern = new RegExp(CUE_PATTERN.source, 'g');
  const matches = [];

  for (const match of text.matchAll(pattern)) {
    const hasContent = match[1] !== undefined;
    matches.push({
      index: match.index,
      length: match[0].length,
      contentIndex: hasContent
        ? match.index + match[0].lastIndexOf(match[1])
        : match.index + match[0].length - 1,
      content: hasContent ? match[1] : '',
    });
  }

  return matches;
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
 * Rewrite every cue tag into the canonical `[cue …]` spelling.
 *
 * Used at the file boundary, so a script that leaves the app carries the
 * current syntax and one that arrives is brought up to it.
 */
export function normalizingTags(text) {
  let result = text;

  // Back to front, so replacing a tag doesn't shift the ones still to come.
  for (const match of cueMatches(text).reverse()) {
    result = result.slice(0, match.index)
      + cueTag(match.content)
      + result.slice(match.index + match.length);
  }

  return result;
}

/** Strip every cue tag out, for somewhere a cue would only be noise. */
export function withoutCues(text) {
  let result = text;
  for (const match of cueMatches(text).reverse()) {
    result = result.slice(0, match.index) + result.slice(match.index + match.length);
  }
  return result;
}

/**
 * Split a single line into spoken text and cue runs.
 *
 * Shared by the editor and the display so both render cues identically.
 */
export function segments(line) {
  const matches = cueMatches(line);
  if (matches.length === 0) return [{ type: 'text', value: line }];

  const result = [];
  let lastEnd = 0;

  for (const match of matches) {
    if (match.index > lastEnd) {
      const before = line.slice(lastEnd, match.index);
      if (before.trim()) result.push({ type: 'text', value: before });
    }
    result.push({ type: 'cue', value: match.content });
    lastEnd = match.index + match.length;
  }

  if (lastEnd < line.length) {
    const after = line.slice(lastEnd);
    if (after.trim()) result.push({ type: 'text', value: after });
  }

  return result;
}

/**
 * The text to splice in for an empty cue at `location`, spaced so it doesn't
 * collide with the words either side of it, and how far into that text the
 * caret belongs — between the brackets, ready for the cue to be typed.
 */
export function emptyCueInsertion(text, location) {
  const previous = location > 0 ? text[location - 1] : '';
  const next = location < text.length ? text[location] : '';

  const isSpace = (ch) => ch !== '' && /\s/.test(ch);
  const leading = previous !== '' && !isSpace(previous) ? ' ' : '';
  const trailing = next !== '' && !isSpace(next) ? ' ' : '';

  return {
    text: leading + EMPTY_CUE_TAG + trailing,
    caretOffset: leading.length + CUE_TAG_PREFIX.length,
  };
}

/**
 * The range of an untouched `[cue ]` the caret is sitting inside, if this
 * backspace is the one deleting its trailing space. A cue with anything written
 * in it deletes a character at a time like ordinary text.
 */
export function emptyCueSurrounding(location, text) {
  const start = location - (CUE_TAG_PREFIX.length - 1);
  if (start < 0 || start + EMPTY_CUE_TAG.length > text.length) return null;
  if (text.slice(start, start + EMPTY_CUE_TAG.length) !== EMPTY_CUE_TAG) return null;
  return { index: start, length: EMPTY_CUE_TAG.length };
}

/** Format time as mm:ss, negative when the run has gone over. */
export function formatTime(seconds) {
  const negative = seconds < 0;
  const abs = Math.abs(seconds);
  const text = `${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`;
  return negative ? `-${text}` : text;
}
