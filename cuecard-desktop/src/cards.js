/**
 * Cards mode's viewer: one card at a time, turned with Back and Next, the
 * arrow keys, or a swipe on the trackpad.
 *
 * The time at the top counts down the cards timer, or up from when the deck
 * was opened when none is set, as on the phone.
 */

import { cards as cardsOf, formatTime, wordCount } from './parser.js';
import { settings, timerColor, timerDuration, timerStyle } from './settings.js';
import { cardHtml } from './ui.js';
import { hydrateImages } from './images.js';
import { icon } from './icons.js';
import { track, trackClick } from './tauri.js';

/** How much sideways scrolling counts as a swipe. */
const SWIPE_DISTANCE = 90;

export function createCardsViewer(root, { onClose } = {}) {
  root.innerHTML = `
    <div class="prompter-bar" data-tauri-drag-region>
      <div class="prompter-bar-side">
        <button class="glass-btn" data-role="close" aria-label="Close" title="Close (Esc)">${icon('xmark', 16)}</button>
      </div>
      <div class="prompter-heading" data-tauri-drag-region>
        <span class="prompter-title" data-tauri-drag-region></span>
        <span class="prompter-subtitle" data-tauri-drag-region></span>
      </div>
      <div class="prompter-bar-side is-trailing">
        <span class="prompter-timer">00:00</span>
      </div>
    </div>

    <div class="deck-dots" aria-hidden="true"></div>

    <div class="deck-stage">
      <div class="deck-card" aria-live="polite"><div class="deck-card-text"></div></div>
      <div class="deck-done" hidden>
        <span class="deck-done-icon">${icon('check', 30, 2.2)}</span>
        <h3 class="empty-title">All cards done</h3>
        <p class="empty-text">Press ← to bring the last card back, or start over.</p>
        <button class="filled-btn" data-role="over">Start Over</button>
      </div>
    </div>

    <div class="deck-controls">
      <button class="glass-btn is-round" data-role="back" aria-label="Previous Card" title="Previous card (←)">${icon('chevronLeft', 21)}</button>
      <button class="deck-next" data-role="next"><span></span>${icon('chevronRight', 18, 2.2)}</button>
    </div>`;

  const el = {
    title: root.querySelector('.prompter-title'),
    subtitle: root.querySelector('.prompter-subtitle'),
    timer: root.querySelector('.prompter-timer'),
    dots: root.querySelector('.deck-dots'),
    stage: root.querySelector('.deck-stage'),
    card: root.querySelector('.deck-card'),
    text: root.querySelector('.deck-card-text'),
    done: root.querySelector('.deck-done'),
    back: root.querySelector('[data-role="back"]'),
    next: root.querySelector('[data-role="next"]'),
    nextLabel: root.querySelector('[data-role="next"] span'),
  };

  const deck = {
    open: false,
    cards: [],
    /** The card on top. One past the last is the deck done. */
    index: 0,
    openedAt: 0,
    timer: null,
    swipe: 0,
    swipeTimer: null,
  };

  const isDone = () => deck.index >= deck.cards.length;

  function render(direction = 0) {
    const total = deck.cards.length;
    el.done.hidden = !isDone();
    el.card.hidden = isDone();
    if (!isDone()) {
      el.text.innerHTML = cardHtml(deck.cards[deck.index]);
      el.text.style.fontSize = `${settings.cardsFontSize}px`;
      fit();
      hydrateImages(el.text, () => deck.open && !isDone() && fit());
      if (direction) {
        el.card.animate(
          [
            { transform: `translateX(${direction * 36}px)`, opacity: 0 },
            { transform: 'translateX(0)', opacity: 1 },
          ],
          { duration: 220, easing: 'cubic-bezier(0.32, 0.9, 0.36, 1)' }
        );
      }
    }

    el.subtitle.textContent = isDone() ? 'Done' : `Card ${deck.index + 1} of ${total}`;
    el.back.disabled = deck.index === 0;
    el.nextLabel.textContent = isDone() ? 'Done' : deck.index === total - 1 ? 'Finish' : 'Next';
    el.next.disabled = isDone();
    renderDots();
  }

  /** A card too long for the window shrinks to fit rather than being cut off. */
  function fit() {
    let size = settings.cardsFontSize;
    el.text.style.fontSize = `${size}px`;
    const room = el.card.clientHeight - 8;
    while (size > 12 && el.text.scrollHeight > room) {
      size -= 2;
      el.text.style.fontSize = `${size}px`;
    }
  }

  /** A dot a card. A long deck shows the dots around the card on top, the ones
   *  at either edge shrunk to say there are more. */
  function renderDots() {
    const total = deck.cards.length;
    const shown = 9;
    let from = 0;
    if (total > shown) from = Math.min(Math.max(deck.index - Math.floor(shown / 2), 0), total - shown);
    const to = Math.min(from + shown, total);
    const dots = [];
    for (let i = from; i < to; i += 1) {
      const edge = (i === from && from > 0) || (i === to - 1 && to < total);
      const state = isDone() || i === deck.index ? ' is-current' : i < deck.index ? ' is-past' : '';
      dots.push(`<span class="deck-dot${state}${edge ? ' is-edge' : ''}"></span>`);
    }
    el.dots.innerHTML = dots.join('');
    el.dots.hidden = total < 2;
  }

  function updateTimer() {
    const style = timerStyle('cards');
    const duration = timerDuration('cards');
    const elapsed = Math.floor((performance.now() - deck.openedAt) / 1000);
    const remaining = duration - elapsed;
    el.timer.textContent = formatTime(duration > 0 ? remaining : elapsed);
    el.timer.style.color = `var(--color-${timerColor(style, remaining, duration)})`;
  }

  function go(by) {
    const next = Math.min(Math.max(deck.index + by, 0), deck.cards.length);
    if (next === deck.index) return;
    deck.index = next;
    track('card_turn', { card_index: deck.index, total_cards: deck.cards.length });
    render(by);
  }

  const next = () => go(1);
  const previous = () => go(-1);

  function startOver() {
    trackClick('start_over', 'cards');
    deck.index = 0;
    render(-1);
  }

  el.next.addEventListener('click', () => {
    trackClick('next_card', 'cards');
    next();
  });
  el.back.addEventListener('click', () => {
    trackClick('previous_card', 'cards');
    previous();
  });
  root.querySelector('[data-role="over"]').addEventListener('click', startOver);
  root.querySelector('[data-role="close"]').addEventListener('click', () => {
    trackClick('cards_close', 'cards');
    close();
  });

  // Two fingers sideways on a trackpad turn the card, once per swipe.
  el.stage.addEventListener('wheel', (event) => {
    if (Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
    event.preventDefault();
    if (deck.swipeTimer === 'locked') return;
    deck.swipe += event.deltaX;
    clearTimeout(deck.swipeTimer);
    deck.swipeTimer = setTimeout(() => {
      deck.swipe = 0;
      deck.swipeTimer = null;
    }, 160);
    if (Math.abs(deck.swipe) > SWIPE_DISTANCE) {
      const by = deck.swipe > 0 ? 1 : -1;
      deck.swipe = 0;
      clearTimeout(deck.swipeTimer);
      deck.swipeTimer = 'locked';
      setTimeout(() => {
        deck.swipeTimer = null;
      }, 450);
      go(by);
    }
  }, { passive: false });

  function onKeyDown(event) {
    if (!deck.open) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (document.querySelector('.alert-layer, .sheet-layer')) return;
    const key = event.key;
    if (key === 'Escape') {
      event.preventDefault();
      close();
    } else if (key === 'ArrowRight' || key === 'ArrowDown' || key === ' ' || key === 'PageDown' || key === 'Enter') {
      event.preventDefault();
      next();
    } else if (key === 'ArrowLeft' || key === 'ArrowUp' || key === 'PageUp' || key === 'Backspace') {
      event.preventDefault();
      previous();
    } else if (key === 'Home' || key === '0') {
      event.preventDefault();
      deck.index = 0;
      render(-1);
    } else if (key === 'End') {
      event.preventDefault();
      deck.index = Math.max(deck.cards.length - 1, 0);
      render(1);
    }
  }

  const onResize = () => deck.open && !isDone() && fit();
  window.addEventListener('resize', onResize);

  function open({ text, title }) {
    deck.cards = cardsOf(text);
    if (!deck.cards.length) return false;
    deck.open = true;
    deck.index = 0;
    deck.openedAt = performance.now();
    el.title.textContent = title;
    root.hidden = false;
    document.addEventListener('keydown', onKeyDown, true);
    track('cards_started', { card_count: deck.cards.length, word_count: wordCount(text), timer_duration: timerDuration('cards') });
    requestAnimationFrame(() => render());
    updateTimer();
    deck.timer = setInterval(updateTimer, 250);
    return true;
  }

  function close() {
    if (!deck.open) return;
    track('cards_closed', {
      elapsed_time: Math.floor((performance.now() - deck.openedAt) / 1000),
      cards_seen: Math.min(deck.index + 1, deck.cards.length),
    });
    deck.open = false;
    clearInterval(deck.timer);
    document.removeEventListener('keydown', onKeyDown, true);
    root.hidden = true;
    onClose?.();
  }

  return {
    open,
    close,
    next,
    previous,
    restart: () => {
      deck.index = 0;
      deck.openedAt = performance.now();
      render(-1);
      updateTimer();
    },
    isOpen: () => deck.open,
    restyle: () => deck.open && render(),
  };
}
