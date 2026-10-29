/**
 * CueCard — script parsing
 *
 * A port of the iOS app's `TeleprompterParser`, so both apps agree on what a
 * script says. `[smile]` is the form to write: anything in brackets is a cue.
 * `[cue smile]` and `[note smile]` are older spellings and mean exactly the
 * same thing, so scripts written before keep working; importing, exporting or
 * opening the app rewrites them to `[smile]`. A bare `[cue]` is a cue that
 * says "cue", the one Insert Cue writes for the user to type over.
 *
 * A tag only counts once its closing bracket is there — `[smi` is still plain
 * text, so nothing changes under the user mid-word. Cues can't span lines for
 * the same reason: a stray `[` shouldn't swallow the paragraphs after it.
 *
 * Every cue is drawn in the one colour from Settings. An older `[cue:green …]`
 * still parses, but the colour name is ignored and dropped on the next import
 * or export.
 *
 * The phone app's `[anchor]`, `[separator]` and `[image …]` tags aren't cues.
 * They're read past and never shown, so a script written there still reads as
 * the words it is made of.
 */

/** Anything in brackets on one line, the text inside in group 1. */
const TAG_PATTERN = /\[([^\]\n]*)\]/g;

/** The phone app's tags that aren't cues. */
const isReservedTag = (inside) =>
  /^(?:anchor|separator)$/i.test(inside) || /^image[ \t]+[A-Za-z0-9-]+\.[A-Za-z0-9]+$/.test(inside);

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

/** Build the tag for a cue. */
export function cueTag(text) {
  return CUE_TAG_PREFIX + (text || '').trim() + CUE_TAG_SUFFIX;
}

/**
 * Find every tag in the text, in order, each one saying whether it is a cue.
 *
 * An older `[cue …]` keeps its prefix as tag syntax, outside the cue's text.
 */
function tagMatches(text) {
  const pattern = new RegExp(TAG_PATTERN.source, 'g');
  const matches = [];

  for (const match of text.matchAll(pattern)) {
    const inside = match[1];
    const prefix = inside.match(LEGACY_PREFIX)?.[0].length ?? 0;

    matches.push({
      isCue: !isReservedTag(inside),
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
 * Rewrite every cue tag into the canonical `[…]` spelling.
 *
 * Used at the file boundary, so a script that leaves the app carries the
 * current syntax and one that arrives is brought up to it.
 */
export function normalizingTags(text) {
  let result = text;

  // Back to front, so replacing a tag doesn't shift the ones still to come.
  for (const match of cueMatches(text).reverse()) {
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

/**
 * Split a single line into spoken text and cue runs, foreign tags dropped.
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
      if (before.trim()) result.push({ type: 'text', value: before });
    }
    if (match.isCue) result.push({ type: 'cue', value: match.content });
    lastEnd = match.index + match.length;
  }

  if (lastEnd < line.length) {
    const after = line.slice(lastEnd);
    if (after.trim()) result.push({ type: 'text', value: after });
  }

  return result;
}

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

/** Format time as mm:ss, negative when the run has gone over. */
export function formatTime(seconds) {
  const negative = seconds < 0;
  const abs = Math.abs(seconds);
  const text = `${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`;
  return negative ? `-${text}` : text;
}

/**
 * The colour every delivery cue is drawn in.
 *
 * One colour covers the whole app — the choice lives in Settings, not in the
 * script — so changing it recolours every cue in every script at once. The
 * stored value has to stay stable once shipped: renaming one resets that
 * user's choice back to the default.
 */
export const CUE_COLORS = ['pink', 'yellow', 'green', 'blue', 'purple', 'red'];

/** What cues are drawn in until the user picks something else. */
export const DEFAULT_CUE_COLOR = 'pink';

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
  return base || 'Imported Script';
}
