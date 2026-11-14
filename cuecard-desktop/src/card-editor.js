/**
 * Cards mode's editor: one box a card, each one editable on its own, with how
 * much of it shows against the card's limit.
 *
 * The deck is stored with a `[separator]` between cards, as on the phone, and
 * the separator is never shown here: each box is a card.
 */

import { createEditor } from './editor.js';
import { CARD_CHARACTER_LIMIT, editableCards, measureCard, scriptForCards } from './parser.js';
import { icon } from './icons.js';

export function createCardEditor(root, { onChange, onFocusChange, onKeyDown, onImages } = {}) {
  root.classList.add('card-editor');
  root.innerHTML = `
    <div class="card-list"></div>
    <button class="add-card-btn" data-role="add">${icon('plus', 15)}<span>Create New Card</span></button>`;

  const list = root.querySelector('.card-list');
  const addButton = root.querySelector('[data-role="add"]');

  /** One `{ el, editor, counter }` a card. */
  let boxes = [];
  let lastFocused = null;
  let firstPlaceholder = '';

  const texts = () => boxes.map((box) => box.editor.getText());

  function emit() {
    onChange?.(scriptForCards(texts()));
  }

  function updateBox(box, index) {
    box.el.querySelector('.card-number').textContent = `Card ${index + 1}`;
    const measure = measureCard(box.editor.getText());
    box.counter.textContent = `${measure.length}/${CARD_CHARACTER_LIMIT}`;
    box.el.classList.toggle('is-over', measure.length > CARD_CHARACTER_LIMIT);
    box.el.querySelector('[data-role="remove"]').hidden = boxes.length < 2;
  }

  const updateAll = () => {
    boxes.forEach(updateBox);
    boxes.forEach((box, index) => box.editor.setPlaceholder(index === 0 ? firstPlaceholder : 'Write this card…'));
  };

  function makeBox(text) {
    const el = document.createElement('div');
    el.className = 'card-box';
    el.innerHTML = `
      <div class="card-box-head">
        <span class="card-number"></span>
        <span class="card-count"></span>
        <button class="icon-btn is-small card-remove" data-role="remove" aria-label="Remove Card" title="Remove Card">${icon('trash', 13)}</button>
      </div>
      <div class="card-box-editor"></div>`;

    const box = { el, counter: el.querySelector('.card-count'), editor: null };
    box.editor = createEditor(el.querySelector('.card-box-editor'), {
      auto: true,
      onImages,
      onChange: () => {
        updateBox(box, boxes.indexOf(box));
        emit();
      },
      onFocusChange: (focused) => {
        el.classList.toggle('is-focused', focused);
        if (focused) lastFocused = box;
        onFocusChange?.(focused);
      },
      onKeyDown: (event) => handleKey(event, box),
    });
    box.editor.setText(text);
    el.querySelector('[data-role="remove"]').addEventListener('click', () => removeBox(box));
    // A click on the card's padding lands in its text.
    el.addEventListener('mousedown', (event) => {
      if (event.target.closest('.editor-input, button')) return;
      event.preventDefault();
      box.editor.focus();
    });
    return box;
  }

  /** ⌘↩ makes the next card; Backspace in an empty card takes it away. */
  function handleKey(event, box) {
    if (onKeyDown?.(event)) return true;
    const mod = event.metaKey || event.ctrlKey;
    if (mod && event.key === 'Enter') {
      event.preventDefault();
      addBox(boxes.indexOf(box) + 1);
      return true;
    }
    if (event.key === 'Backspace' && !box.editor.getText() && boxes.length > 1) {
      event.preventDefault();
      const index = boxes.indexOf(box);
      removeBox(box, { focus: Math.max(index - 1, 0) });
      return true;
    }
    return false;
  }

  function addBox(at = boxes.length) {
    const box = makeBox('');
    boxes.splice(at, 0, box);
    list.insertBefore(box.el, list.children[at] || null);
    updateAll();
    emit();
    box.editor.focus();
    box.el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    return box;
  }

  function removeBox(box, { focus = null } = {}) {
    if (boxes.length < 2) return;
    const index = boxes.indexOf(box);
    boxes.splice(index, 1);
    box.el.remove();
    if (lastFocused === box) lastFocused = null;
    updateAll();
    emit();
    const next = boxes[focus ?? Math.min(index, boxes.length - 1)];
    if (focus !== null) {
      next?.editor.focus();
      const input = next?.editor.element;
      if (input) input.setSelectionRange(input.value.length, input.value.length);
    }
  }

  addButton.addEventListener('click', () => addBox());

  return {
    /** Lay the deck out again from its script. Only when it changed from outside. */
    setText(script) {
      if (scriptForCards(texts()) === script && boxes.length) return;
      const cards = editableCards(script);
      list.innerHTML = '';
      boxes = cards.map(makeBox);
      boxes.forEach((box) => list.appendChild(box.el));
      lastFocused = null;
      updateAll();
    },

    setPlaceholder(text) {
      firstPlaceholder = text;
      boxes[0]?.editor.setPlaceholder(text);
    },

    /** The card being written in, or the last one written in. */
    activeEditor: () => boxes.find((box) => box.editor.isFocused())?.editor || lastFocused?.editor || boxes[0]?.editor,

    focus() {
      (lastFocused || boxes[0])?.editor.focus();
    },

    isFocused: () => boxes.some((box) => box.editor.isFocused()),
    addCard: () => addBox(),
    repaint: () => boxes.forEach((box) => box.editor.repaint()),
    scrollToTop: () => root.scrollTo(0, 0),
  };
}
