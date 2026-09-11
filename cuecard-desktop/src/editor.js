/**
 * The script editor: always editable, with cues coloured as they are written.
 *
 * The text lives in a real textarea, so the caret, selection, undo and spell
 * checking are the system's. A backdrop behind it holds the same text with the
 * cues coloured, and the textarea's own glyphs are transparent — so what you
 * see is the backdrop, and what you edit is the textarea. The two only line up
 * if their metrics match exactly, which is why the colouring changes colour and
 * nothing else.
 */

import {
  CUE_TAG_PREFIX,
  EMPTY_CUE_TAG,
  cueMatches,
  cueTagContaining,
  emptyCueInsertion,
  emptyCueSurrounding,
} from './parser.js';
import { escapeHtml } from './ui.js';

export function createEditor(root, { onChange, onFocusChange } = {}) {
  root.classList.add('editor');
  root.innerHTML = `
    <div class="editor-backdrop" aria-hidden="true"><div class="editor-highlight"></div></div>
    <textarea class="editor-input" spellcheck="true" autocapitalize="sentences" autocomplete="off"></textarea>
    <p class="editor-placeholder" aria-hidden="true"></p>`;

  const backdrop = root.querySelector('.editor-backdrop');
  const highlight = root.querySelector('.editor-highlight');
  const input = root.querySelector('.editor-input');
  const placeholder = root.querySelector('.editor-placeholder');

  /** Colour the cues. Every piece is escaped separately, so the offsets the
   *  parser found still point at the right characters. */
  function paint() {
    const text = input.value;
    let html = '';
    let last = 0;

    for (const match of cueMatches(text)) {
      html += escapeHtml(text.slice(last, match.index));
      const opening = text.slice(match.index, match.contentIndex);
      const content = match.content;
      const closing = text.slice(match.contentIndex + content.length, match.index + match.length);
      html += `<span class="cue-syntax">${escapeHtml(opening)}</span>`;
      html += `<span class="cue-text">${escapeHtml(content)}</span>`;
      html += `<span class="cue-syntax">${escapeHtml(closing)}</span>`;
      last = match.index + match.length;
    }
    html += escapeHtml(text.slice(last));

    // A trailing newline has no glyphs to give the backdrop its final line, so
    // the two would stop agreeing about how tall the text is.
    highlight.innerHTML = `${html}\n`;
    placeholder.hidden = text.length > 0;
    syncScroll();
  }

  const syncScroll = () => {
    backdrop.scrollTop = input.scrollTop;
    backdrop.scrollLeft = input.scrollLeft;
  };

  /** Edit the text ourselves, then run everything a keystroke would have. */
  function replace(start, end, replacement, caret) {
    input.setRangeText(replacement, start, end, 'end');
    input.selectionStart = input.selectionEnd = caret;
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

  // `[` writes both brackets, and the backspace that follows takes them both
  // back, so a `[` meant literally costs one extra keystroke instead of six.
  input.addEventListener('keydown', (event) => {
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

  return {
    element: input,

    setText(text) {
      if (input.value === text) return;
      input.value = text;
      paint();
    },

    getText: () => input.value,
    focus: () => input.focus(),
    isFocused: () => document.activeElement === input,

    setPlaceholder(text) {
      placeholder.textContent = text;
    },

    /** Drop an empty cue in at the caret and leave the caret inside it. */
    insertCue() {
      input.focus();
      let at = input.selectionEnd;
      const enclosing = cueTagContaining(at, input.value);
      if (enclosing) at = enclosing.index + enclosing.length;
      const insertion = emptyCueInsertion(input.value, at);
      replace(at, at, insertion.text, at + insertion.caretOffset);
    },

    /** Put the caret at the end and show the start of the script. */
    reset() {
      input.scrollTop = 0;
      input.selectionStart = input.selectionEnd = input.value.length;
      syncScroll();
    },

    repaint: paint,
    EMPTY_CUE_TAG,
    CUE_TAG_PREFIX,
  };
}
