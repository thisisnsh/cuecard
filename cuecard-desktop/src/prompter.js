/**
 * The prompter: the screen you present from.
 *
 * The script scrolls at a stated number of rendered lines a minute, counted
 * from the clock rather than the frame rate, and the line being read is held
 * just above the middle of the window. Dragging the script moves the clock with
 * it, so letting go never leaves the two out of step.
 */

import { formatTime } from './parser.js';
import { scriptFontSize, settings, timerDuration } from './settings.js';
import { scriptHtml } from './ui.js';
import { icon } from './icons.js';

/**
 * Where on screen the line being read sits, as a fraction of the window height.
 * Just above centre: high enough to leave the next few lines in view, low
 * enough to read as the middle of the screen rather than the top of it.
 */
const READING_LINE = 0.45;

/** How long the controls stay up after the pointer stops moving, while playing. */
const CONTROLS_LINGER = 2600;

export function createPrompter(root, { onClose, onPlayStateChange } = {}) {
  root.innerHTML = `
    <div class="prompter-bar" data-tauri-drag-region>
      <div class="prompter-bar-side"></div>
      <div class="prompter-heading" data-tauri-drag-region>
        <span class="prompter-title" data-tauri-drag-region></span>
        <span class="prompter-subtitle" data-tauri-drag-region></span>
      </div>
      <div class="prompter-bar-side is-trailing">
        <span class="prompter-timer">00:00</span>
      </div>
    </div>

    <div class="prompter-scroll" tabindex="-1"><div class="prompter-text"></div></div>
    <div class="prompter-fade is-top"></div>
    <div class="prompter-fade is-bottom"></div>

    <div class="prompter-controls">
      <button class="glass-btn is-round" data-role="back" aria-label="Back" title="Back (Esc)">${icon('chevronLeft', 21)}</button>
      <button class="play-btn is-large" data-role="play" aria-label="Play" title="Play (Space)">
        <span class="play-icon">${icon('play', 26)}</span>
        <span class="pause-icon" hidden>${icon('pause', 26)}</span>
      </button>
      <button class="glass-btn is-round" data-role="restart" aria-label="Restart" title="Restart (R)">${icon('restart', 20)}</button>
    </div>`;

  const el = {
    bar: root.querySelector('.prompter-bar'),
    title: root.querySelector('.prompter-title'),
    subtitle: root.querySelector('.prompter-subtitle'),
    timer: root.querySelector('.prompter-timer'),
    scroll: root.querySelector('.prompter-scroll'),
    text: root.querySelector('.prompter-text'),
    controls: root.querySelector('.prompter-controls'),
    play: root.querySelector('[data-role="play"]'),
    playIcon: root.querySelector('.play-icon'),
    pauseIcon: root.querySelector('.pause-icon'),
    restart: root.querySelector('[data-role="restart"]'),
    back: root.querySelector('[data-role="back"]'),
  };

  const run = {
    open: false,
    source: 'script',
    text: '',
    playing: false,
    /** Seconds since the run began — the clock the timer and the script share. */
    elapsed: 0,
    elapsedAtStart: 0,
    startedAt: 0,
    /** The clock reading the current script started from. Slides move this on
     *  instead of the talk timer, so a deck's timer runs across every slide. */
    scrollOrigin: 0,
    /** Whether the run has begun since the last restart. The delay runs on the
     *  first play only; resuming from a pause starts straight away. */
    hasStarted: false,
    countingDown: false,
    countdownValue: 0,
    countdownTimer: null,
    lineOffsets: [],
    programmaticTop: -1,
    frame: null,
    idleTimer: null,
  };

  // =============================================================================
  // RENDERING
  // =============================================================================

  function render() {
    el.text.style.fontSize = `${scriptFontSize()}px`;
    el.text.innerHTML = scriptHtml(run.text);
    layout();
  }

  /** The script is inset from the top by exactly the reading line's distance,
   *  so a line's scroll target is simply its own position in the text. */
  function layout() {
    const height = el.scroll.clientHeight;
    el.text.style.paddingTop = `${Math.round(height * READING_LINE)}px`;
    el.text.style.paddingBottom = `${Math.round(height * (1 - READING_LINE))}px`;
    measure();
  }

  /**
   * One entry per line the script actually wraps into at this size.
   *
   * The rects have to come from the text nodes themselves. A range over the
   * whole container reports one rect per *element*, so a paragraph — however
   * many lines it wrapped into — would measure as a single line, and a script
   * of one paragraph would have nowhere to scroll to at all.
   */
  function measure() {
    const offsets = [];
    const top = el.text.getBoundingClientRect().top + parseFloat(getComputedStyle(el.text).paddingTop || '0');

    const rects = [];
    const walker = document.createTreeWalker(el.text, NodeFilter.SHOW_TEXT);
    const range = document.createRange();
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!node.nodeValue.trim()) continue;
      range.selectNodeContents(node);
      for (const rect of range.getClientRects()) {
        if (rect.height > 0) rects.push(rect);
      }
    }
    rects.sort((a, b) => a.top - b.top);

    let bottom = -Infinity;
    for (const rect of rects) {
      // A cue is set smaller than the words around it, so two rects on one line
      // have different tops. Overlapping rects are the same line.
      if (rect.top >= bottom - 2) {
        offsets.push(rect.top - top);
        bottom = rect.bottom;
      } else {
        offsets[offsets.length - 1] = Math.min(offsets[offsets.length - 1], rect.top - top);
        bottom = Math.max(bottom, rect.bottom);
      }
    }

    run.lineOffsets = offsets;
  }

  const maxScroll = () => Math.max(el.scroll.scrollHeight - el.scroll.clientHeight, 0);

  /** Where the script has to sit for `line` to be on the reading line. */
  function offsetForLine(line) {
    const offsets = run.lineOffsets;
    if (offsets.length === 0) return 0;
    const position = Math.min(Math.max(line, 0), offsets.length - 1);
    const index = Math.min(Math.floor(position), offsets.length - 2);
    if (index < 0) return offsets[0];
    return offsets[index] + (offsets[index + 1] - offsets[index]) * (position - index);
  }

  /** The line sitting on the reading line, for a script at `offset`. */
  function lineForOffset(offset) {
    const offsets = run.lineOffsets;
    if (offsets.length < 2) return 0;
    if (offset <= offsets[0]) return 0;
    for (let i = 0; i < offsets.length - 1; i += 1) {
      if (offset < offsets[i + 1]) {
        const span = offsets[i + 1] - offsets[i] || 1;
        return i + (offset - offsets[i]) / span;
      }
    }
    return offsets.length - 1;
  }

  // =============================================================================
  // THE CLOCK
  // =============================================================================

  const scrollElapsed = () => Math.max(run.elapsed - run.scrollOrigin, 0);

  function applyScroll() {
    const line = (scrollElapsed() * settings.linesPerMinute) / 60;
    const target = Math.min(Math.max(offsetForLine(line), 0), maxScroll());
    if (Math.abs(el.scroll.scrollTop - target) < 0.5) {
      run.programmaticTop = el.scroll.scrollTop;
      return;
    }
    el.scroll.scrollTop = target;
    run.programmaticTop = el.scroll.scrollTop;
  }

  function updateTimer() {
    const duration = timerDuration();
    el.timer.classList.remove('is-delay', 'is-warn', 'is-over', 'is-neutral');

    if (run.countingDown) {
      el.timer.textContent = formatTime(run.countdownValue);
      el.timer.classList.add('is-delay');
      return;
    }
    if (duration <= 0) {
      el.timer.textContent = formatTime(Math.floor(run.elapsed));
      el.timer.classList.add('is-neutral');
      return;
    }

    const remaining = duration - Math.floor(run.elapsed);
    el.timer.textContent = formatTime(remaining);
    if (remaining < 0) el.timer.classList.add('is-over');
    else if (remaining / duration <= 0.2) el.timer.classList.add('is-warn');
  }

  function tick() {
    if (run.playing) run.elapsed = run.elapsedAtStart + (performance.now() - run.startedAt) / 1000;
    updateTimer();
    applyScroll();
    run.frame = requestAnimationFrame(tick);
  }

  function startLoop() {
    if (run.frame === null) run.frame = requestAnimationFrame(tick);
  }

  function stopLoop() {
    if (run.frame !== null) cancelAnimationFrame(run.frame);
    run.frame = null;
  }

  // =============================================================================
  // TRANSPORT
  // =============================================================================

  function beginPlaying() {
    run.playing = true;
    run.hasStarted = true;
    run.elapsedAtStart = run.elapsed;
    run.startedAt = performance.now();
    updateTransport();
    scheduleIdle();
  }

  function startCountdown() {
    run.countingDown = true;
    run.countdownValue = settings.countdownSeconds;
    updateTransport();
    updateTimer();

    run.countdownTimer = setInterval(() => {
      run.countdownValue -= 1;
      if (run.countdownValue <= 0) {
        stopCountdown();
        beginPlaying();
        return;
      }
      updateTimer();
    }, 1000);
  }

  function stopCountdown() {
    clearInterval(run.countdownTimer);
    run.countdownTimer = null;
    run.countingDown = false;
  }

  function play() {
    if (run.playing || run.countingDown) return;
    // Notes arriving from Slides are driven by the deck, not by someone stepping
    // back from the keyboard, so there is nothing to wait for.
    const wants = settings.countdownSeconds > 0 && !run.hasStarted && run.source === 'script';
    if (wants) startCountdown();
    else beginPlaying();
    onPlayStateChange?.(true);
  }

  function pause() {
    if (run.countingDown) {
      stopCountdown();
      updateTransport();
      updateTimer();
      onPlayStateChange?.(false);
      return;
    }
    if (!run.playing) return;
    run.playing = false;
    updateTransport();
    showControls();
    onPlayStateChange?.(false);
  }

  function togglePlay() {
    if (run.playing || run.countingDown) pause();
    else play();
  }

  function restart() {
    stopCountdown();
    run.playing = false;
    run.hasStarted = false;
    run.elapsed = 0;
    run.scrollOrigin = 0;
    el.scroll.scrollTop = 0;
    run.programmaticTop = 0;
    updateTransport();
    updateTimer();
    showControls();
    onPlayStateChange?.(false);
  }

  function updateTransport() {
    const running = run.playing || run.countingDown;
    el.playIcon.hidden = running;
    el.pauseIcon.hidden = !running;
    el.play.setAttribute('aria-label', running ? 'Pause' : 'Play');
    el.play.title = running ? 'Pause (Space)' : 'Play (Space)';
  }

  // =============================================================================
  // CONTROLS THAT GET OUT OF THE WAY
  // =============================================================================

  function showControls() {
    root.classList.remove('is-idle');
    scheduleIdle();
  }

  function scheduleIdle() {
    clearTimeout(run.idleTimer);
    if (!run.playing) return;
    run.idleTimer = setTimeout(() => root.classList.add('is-idle'), CONTROLS_LINGER);
  }

  // =============================================================================
  // SCRUBBING
  // =============================================================================

  el.scroll.addEventListener('scroll', () => {
    if (!run.open) return;
    // Ours, not the reader's.
    if (Math.abs(el.scroll.scrollTop - run.programmaticTop) < 1) return;

    const line = lineForOffset(el.scroll.scrollTop);
    const target = settings.linesPerMinute > 0 ? (line * 60) / settings.linesPerMinute : 0;

    if (run.source === 'slides') {
      // The talk's clock belongs to the talk; move where this slide started from.
      run.scrollOrigin = run.elapsed - target;
    } else {
      run.elapsed = target;
    }
    run.elapsedAtStart = run.elapsed;
    run.startedAt = performance.now();
    run.programmaticTop = el.scroll.scrollTop;
    updateTimer();
    showControls();
  });

  root.addEventListener('mousemove', showControls);
  el.play.addEventListener('click', togglePlay);
  el.restart.addEventListener('click', restart);
  el.back.addEventListener('click', () => close());

  function onKeyDown(event) {
    if (!run.open) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;

    if (event.key === 'Escape') {
      event.preventDefault();
      close();
    } else if (event.key === ' ') {
      event.preventDefault();
      togglePlay();
    } else if (event.key.toLowerCase() === 'r') {
      event.preventDefault();
      restart();
    } else if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      nudge(event.key === 'ArrowDown' ? 1 : -1);
    }
    showControls();
  }

  /** Move the script by whole lines, and the clock with it. */
  function nudge(lines) {
    const seconds = settings.linesPerMinute > 0 ? (lines * 60) / settings.linesPerMinute : 0;
    if (run.source === 'slides') run.scrollOrigin = Math.max(run.scrollOrigin - seconds, run.elapsed - 1e6);
    else run.elapsed = Math.max(run.elapsed + seconds, 0);
    run.elapsedAtStart = run.elapsed;
    run.startedAt = performance.now();
    updateTimer();
  }

  const onResize = () => {
    if (!run.open) return;
    layout();
  };
  window.addEventListener('resize', onResize);

  // =============================================================================
  // OPENING AND CLOSING
  // =============================================================================

  function open({ source = 'script', text = '', title = '', subtitle = '' }) {
    run.open = true;
    run.source = source;
    run.text = text;
    run.elapsed = 0;
    run.scrollOrigin = 0;
    run.hasStarted = false;
    run.playing = false;
    stopCountdown();

    setHeading(title, subtitle);
    root.hidden = false;
    root.classList.remove('is-idle');
    document.addEventListener('keydown', onKeyDown, true);

    // The window has to have laid out before lines can be measured.
    requestAnimationFrame(() => {
      render();
      el.scroll.scrollTop = 0;
      run.programmaticTop = 0;
      updateTimer();
      updateTransport();
      el.scroll.focus({ preventScroll: true });
    });

    startLoop();
  }

  function close() {
    if (!run.open) return;
    run.open = false;
    run.playing = false;
    stopCountdown();
    stopLoop();
    clearTimeout(run.idleTimer);
    document.removeEventListener('keydown', onKeyDown, true);
    root.hidden = true;
    onPlayStateChange?.(false);
    onClose?.();
  }

  function setHeading(title, subtitle) {
    el.title.textContent = title;
    el.subtitle.textContent = subtitle || '';
    el.subtitle.hidden = !subtitle;
  }

  return {
    open,
    close,
    togglePlay,
    restart,
    isOpen: () => run.open,
    isPlaying: () => run.playing,
    source: () => run.source,

    /** Replace the script mid-run — a new slide, or a changed setting. */
    setText(text, { fromSlide = false, title, subtitle } = {}) {
      run.text = text;
      if (title !== undefined) setHeading(title, subtitle);
      // A new slide starts at its own first line; the talk's clock runs on.
      if (fromSlide) {
        run.scrollOrigin = run.elapsed;
        el.scroll.scrollTop = 0;
        run.programmaticTop = 0;
      }
      render();
    },

    /** The script's size or colour changed under it. */
    restyle: render,
  };
}
