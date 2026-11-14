/**
 * The script editor: always editable, with cues, anchors and emphasis drawn as
 * they are written.
 *
 * The text lives in a real textarea, so the caret, selection, undo and spell
 * checking are the system's. A backdrop behind it holds the same text drawn
 * with its styling, and the textarea's own glyphs are transparent — so what
 * you see is the backdrop, and what you edit is the textarea. The two only
 * line up if their metrics match exactly, which is why the styling changes
 * colour and fakes weight, and never touches a glyph's width.
 */

import {
  anchorInsertion,
  cueMatches,
  cueTagContaining,
  emphases,
  emptyCueInsertion,
  emptyCueSurrounding,
  newCueInsertion,
  reservedMatches,
} from './parser.js';
import { escapeHtml } from './ui.js';

/**
 * @param options.auto Grow to fit the text instead of scrolling, for a card.
 */
export function createEditor(root, { onChange, onFocusChange, onKeyDown, auto = false } = {}) {
  root.classList.add('editor');
  root.classList.toggle('is-auto', auto);
  root.innerHTML = `
    <div class="editor-backdrop" aria-hidden="true"><div class="editor-highlight"></div></div>
    <textarea class="editor-input" spellcheck="true" autocapitalize="sentences" autocomplete="off"></textarea>
    <p class="editor-placeholder" aria-hidden="true"></p>`;

  const backdrop = root.querySelector('.editor-backdrop');
  const highlight = root.querySelector('.editor-highlight');
  const input = root.querySelector('.editor-input');
  const placeholder = root.querySelector('.editor-placeholder');

  /**
   * Draw the text. Every character takes the classes of whatever it belongs
   * to — a cue's brackets or its words, an anchor, an emphasis marker or the
   * words it styles — and each run of characters with the same classes is one
   * span, every piece escaped on its own.
   */
  function paint() {
    const text = input.value;
    const classes = new Array(text.length).fill('');
    const add = (from, to, name) => {
      for (let i = from; i < to; i += 1) classes[i] += ` ${name}`;
    };

    const cues = cueMatches(text);
    for (const match of cues) {
      const contentEnd = match.contentIndex + match.content.length;
      add(match.index, match.contentIndex, 'cue-syntax');
      add(match.contentIndex, contentEnd, 'cue-text');
      add(contentEnd, match.index + match.length, 'cue-syntax');
    }
    const reserved = reservedMatches(text);
    for (const match of reserved) add(match.index, match.index + match.length, 'tag-reserved');

    const skipping = [...cues, ...reserved];
    for (const emphasis of emphases(text, skipping)) {
      add(emphasis.open.index, emphasis.open.index + emphasis.open.length, 'em-marker');
      if (emphasis.close) add(emphasis.close.index, emphasis.close.index + emphasis.close.length, 'em-marker');
      add(emphasis.content.index, emphasis.content.index + emphasis.content.length, `em-${emphasis.style}`);
    }

    let html = '';
    let runStart = 0;
    for (let i = 1; i <= text.length; i += 1) {
      if (i < text.length && classes[i] === classes[runStart]) continue;
      const piece = escapeHtml(text.slice(runStart, i));
      html += classes[runStart] ? `<span class="${classes[runStart].trim()}">${piece}</span>` : piece;
      runStart = i;
    }

    // A trailing newline has no glyphs to give the backdrop its final line, so
    // the two would stop agreeing about how tall the text is.
    highlight.innerHTML = `${html}\n`;
    placeholder.hidden = text.length > 0;
    syncScroll();
  }

  const syncScroll = () => {
    if (auto) return;
    backdrop.scrollTop = input.scrollTop;
    backdrop.scrollLeft = input.scrollLeft;
  };

  /** Edit the text ourselves, then run everything a keystroke would have.
   *  `execCommand` keeps the change on the textarea's own undo stack. */
  function replace(start, end, replacement, caret, selectionEnd = caret) {
    input.focus();
    input.setSelectionRange(start, end);
    const done = document.execCommand?.('insertText', false, replacement);
    if (!done || input.value.slice(start, start + replacement.length) !== replacement) {
      input.setRangeText(replacement, start, end, 'end');
    }
    input.setSelectionRange(caret, selectionEnd);
    paint();
    onChange?.(input.value);
  }

  input.addEventListener('input', () => {
    paint();
    onChange?.(input.value);
  });
  input.addEventListener('scroll', syncScroll);
  input.addEventListener('focus', () => onFocusChange?.(true));
  input.addEventListener('blur', () => onFocusChange?.(false));

  // `[` writes both brackets, and the backspace that follows takes the closing
  // one back, so a `[` meant literally costs one extra keystroke.
  input.addEventListener('keydown', (event) => {
    if (onKeyDown?.(event)) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (input.selectionStart !== input.selectionEnd) return;

    const caret = input.selectionStart;
    const text = input.value;

    if (event.key === '[') {
      event.preventDefault();
      // Cues don't nest, and in there both brackets are already written.
      if (cueTagContaining(caret, text)) return;
      const insertion = emptyCueInsertion(text, caret);
      replace(caret, caret, insertion.text, caret + insertion.caretOffset);
      return;
    }

    if (event.key === 'Backspace' && caret > 0) {
      const empty = emptyCueSurrounding(caret - 1, text);
      if (!empty) return;
      event.preventDefault();
      replace(empty.index, empty.index + empty.length, '[', empty.index + 1);
    }
  });

  /** Where something new goes: after the cue the caret is in, if it's in one. */
  const insertionPoint = () => {
    let at = input.selectionEnd;
    const enclosing = cueTagContaining(at, input.value);
    if (enclosing) at = enclosing.index + enclosing.length;
    return at;
  };

  return {
    element: input,
    root,

    setText(text) {
      if (input.value === text) return;
      input.value = text;
      paint();
    },

    getText: () => input.value,
    focus: () => input.focus({ preventScroll: auto }),
    isFocused: () => document.activeElement === input,

    setPlaceholder(text) {
      placeholder.textContent = text;
    },

    /** Drop a `[cue]` in at the caret with its text selected to type over. */
    insertCue() {
      input.focus();
      const at = insertionPoint();
      const insertion = newCueInsertion(input.value, at);
      replace(at, at, insertion.text, at + insertion.selectionStart, at + insertion.selectionEnd);
    },

    /** Drop an `[anchor]` in at the caret. */
    insertAnchor() {
      input.focus();
      const at = insertionPoint();
      const insertion = anchorInsertion(input.value, at);
      replace(at, at, insertion.text, at + insertion.caretOffset);
    },

    /**
     * Bold or italic for the selected words: `*` or `_` written around them,
     * or taken away if they're already there. With nothing selected, a pair is
     * written with the caret between them, ready to type in.
     */
    toggleEmphasis(style) {
      input.focus();
      const marker = style === 'bold' ? '*' : '_';
      const text = input.value;
      let start = input.selectionStart;
      let end = input.selectionEnd;

      // Leave the space either side of the words out of the markers.
      while (start < end && /\s/.test(text[start])) start += 1;
      while (end > start && /\s/.test(text[end - 1])) end -= 1;

      if (start === end) {
        replace(start, end, marker + marker, start + 1);
        return;
      }

      const selected = text.slice(start, end);
      const isWrapped = (s) => s.length > 2 && s.startsWith(marker) && s.endsWith(marker);
      if (isWrapped(selected)) {
        const inner = selected.slice(1, -1);
        replace(start, end, inner, start, start + inner.length);
        return;
      }
      if (text[start - 1] === marker && text[end] === marker) {
        replace(start - 1, end + 1, selected, start - 1, end - 1);
        return;
      }
      // Emphasis doesn't run across lines, so each line is wrapped on its own.
      const wrapped = selected
        .split('\n')
        .map((line) => {
          const words = line.trim();
          if (!words) return line;
          const at = line.indexOf(words);
          return line.slice(0, at) + marker + words + marker + line.slice(at + words.length);
        })
        .join('\n');
      replace(start, end, wrapped, start, start + wrapped.length);
    },

    /** Put the caret at the end and show the start of the script. */
    reset() {
      input.scrollTop = 0;
      input.selectionStart = input.selectionEnd = input.value.length;
      syncScroll();
    },

    /** Put the caret at the very start. */
    caretToStart() {
      input.setSelectionRange(0, 0);
    },

    repaint: paint,
  };
}
