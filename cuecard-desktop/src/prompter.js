/**
 * The prompter: the screen you present from.
 *
 * The script scrolls at a stated number of rendered lines a minute, counted
 * from the clock rather than the frame rate, and the line being read is held
 * on the reading line. Dragging the script moves where it scrolls from and
 * nothing else: the timer is the talk's, not the script's.
 *
 * As on the phone, the reading line can be moved with the guide in the margin,
 * `[anchor]`s are jumped between with the buttons at either end, and the text
 * can be flipped for a teleprompter's glass.
 */

import { formatTime, wordCount } from './parser.js';
import { clamp, setSetting, settings, timerColor, timerDuration, timerStyle } from './settings.js';
import { scriptHtml } from './ui.js';
import { hydrateImages } from './images.js';
import { icon } from './icons.js';
import { track, trackClick } from './tauri.js';

/** Where the line being read sits with the guide turned off: just above centre. */
const DEFAULT_READING_LINE = 0.45;

/** How long the controls stay up after the pointer stops moving, while playing. */
const CONTROLS_LINGER = 2600;

/** Lines from an anchor that still count as being on it. */
const ANCHOR_SLACK = 0.25;

export function createPrompter(root, { onClose, onPlayStateChange } = {}) {
  root.innerHTML = `
    <div class="prompter-bar" data-tauri-drag-region>
      <div class="prompter-bar-side">
        <button class="glass-btn" data-role="back" aria-label="Close" title="Close (Esc)">${icon('xmark', 16)}</button>
      </div>
      <div class="prompter-heading" data-tauri-drag-region>
        <span class="prompter-title" data-tauri-drag-region></span>
        <span class="prompter-subtitle" data-tauri-drag-region></span>
      </div>
      <div class="prompter-bar-side is-trailing">
        <span class="prompter-timer">00:00</span>
      </div>
    </div>

    <div class="prompter-stage">
      <div class="prompter-scroll" tabindex="-1"><div class="prompter-text"></div></div>
      <div class="prompter-fade is-top"></div>
      <div class="prompter-fade is-bottom"></div>
      <div class="reading-guide" hidden>
        <div class="reading-guide-rule"></div>
        <button class="reading-guide-handle" aria-label="Reading Guide" title="Drag to move the reading line">
          <svg width="12" height="16" viewBox="0 0 12 16" aria-hidden="true"><path d="M2 1.5 10.5 8 2 14.5Z" fill="currentColor"/></svg>
        </button>
      </div>
    </div>

    <div class="prompter-controls">
      <button class="glass-btn is-round anchor-btn" data-role="prev-anchor" aria-label="Previous Anchor" title="Previous anchor (←)">${icon('anchorPrev', 19)}</button>
      <div class="prompter-transport">
        <button class="glass-btn is-round" data-role="restart" aria-label="Restart" title="Restart (R)">${icon('restart', 19)}</button>
        <button class="play-btn is-large" data-role="play" aria-label="Play" title="Play (Space)">
          <span class="play-icon">${icon('play', 26)}</span>
          <span class="pause-icon" hidden>${icon('pause', 26)}</span>
          <span class="countdown-number" hidden></span>
        </button>
        <span class="transport-spacer"></span>
      </div>
      <button class="glass-btn is-round anchor-btn" data-role="next-anchor" aria-label="Next Anchor" title="Next anchor (→)">${icon('anchorNext', 19)}</button>
    </div>`;

  const el = {
    bar: root.querySelector('.prompter-bar'),
    title: root.querySelector('.prompter-title'),
    subtitle: root.querySelector('.prompter-subtitle'),
    timer: root.querySelector('.prompter-timer'),
    stage: root.querySelector('.prompter-stage'),
    scroll: root.querySelector('.prompter-scroll'),
    text: root.querySelector('.prompter-text'),
    fadeTop: root.querySelector('.prompter-fade.is-top'),
    fadeBottom: root.querySelector('.prompter-fade.is-bottom'),
    guide: root.querySelector('.reading-guide'),
    handle: root.querySelector('.reading-guide-handle'),
    controls: root.querySelector('.prompter-controls'),
    play: root.querySelector('[data-role="play"]'),
    playIcon: root.querySelector('.play-icon'),
    pauseIcon: root.querySelector('.pause-icon'),
    countdown: root.querySelector('.countdown-number'),
    restart: root.querySelector('[data-role="restart"]'),
    back: root.querySelector('[data-role="back"]'),
    prevAnchor: root.querySelector('[data-role="prev-anchor"]'),
    nextAnchor: root.querySelector('[data-role="next-anchor"]'),
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
    /** The clock reading the script's first line sits at. Scrolling, nudging,
     *  anchors and a new slide move this; the talk's timer never budges. */
    scrollOrigin: 0,
    /** Whether the run has begun since the last restart. The countdown runs on
     *  the first play only; resuming from a pause starts straight away. */
    hasStarted: false,
    countingDown: false,
    countdownValue: 0,
    countdownTimer: null,
    lineOffsets: [],
    /** The line each anchor sits on, in order, with the top and the end. */
    anchorLines: [],
    hasAnchors: false,
    programmaticTop: -1,
    frame: null,
    idleTimer: null,
    /** The reading line's distance from the top of the stage, in pixels. */
    readingTop: 0,
    dragging: null,
  };

  // =============================================================================
  // RENDERING
  // =============================================================================

  const lineHeight = () => settings.fontSize * 1.38;

  function render() {
    el.text.style.fontSize = `${settings.fontSize}px`;
    el.text.innerHTML = scriptHtml(run.text);
    applyFlip();
    layout();
    // A picture takes its room once it's loaded, so the lines move under it.
    hydrateImages(el.text, () => {
      if (run.open) layout();
    });
  }

  function applyFlip() {
    const x = settings.mirrorsText ? -1 : 1;
    const y = settings.flipsTextVertically ? -1 : 1;
    el.scroll.style.transform = x === 1 && y === 1 ? '' : `scale(${x}, ${y})`;
  }

  /** The highest and lowest the reading line goes: clear of both fades. */
  function readingBounds() {
    const height = el.stage.clientHeight;
    const top = el.fadeTop.offsetHeight * 0.75;
    const bottom = height - el.fadeBottom.offsetHeight - lineHeight() - 70;
    return [top, Math.max(bottom, top)];
  }

  /** Where the line being read starts, from the top of the stage. */
  function readingTop() {
    const height = el.stage.clientHeight;
    if (!settings.showsReadingGuide) return Math.round(height * DEFAULT_READING_LINE);
    const [min, max] = readingBounds();
    return Math.round(min + (max - min) * settings.readingGuidePosition);
  }

  /** The script is inset from the top by exactly the reading line's distance,
   *  so a line's scroll target is simply its own position in the text. */
  function layout() {
    const height = el.stage.clientHeight;
    run.readingTop = readingTop();
    el.text.style.paddingTop = `${run.readingTop}px`;
    el.text.style.paddingBottom = `${Math.max(height - run.readingTop, 0)}px`;
    measure();
    placeGuide(run.readingTop);
  }

  /** The guide on the line being read, where it shows once flipped. */
  function placeGuide(top) {
    el.guide.hidden = !settings.showsReadingGuide;
    if (el.guide.hidden) return;
    const height = el.stage.clientHeight;
    const center = top + lineHeight() / 2;
    const shown = settings.flipsTextVertically ? height - center : center;
    el.guide.style.top = `${shown}px`;
    el.guide.classList.toggle('is-mirrored', settings.mirrorsText);
  }

  /**
   * One entry per line the script actually wraps into at this size, and the
   * line each anchor sits on.
   *
   * The rects have to come from the text nodes themselves. A range over the
   * whole container reports one rect per *element*, so a paragraph — however
   * many lines it wrapped into — would measure as a single line, and a script
   * of one paragraph would have nowhere to scroll to at all.
   */
  function measure() {
    const offsets = [];
    const flipY = settings.flipsTextVertically;
    const textBox = el.text.getBoundingClientRect();
    const padding = parseFloat(getComputedStyle(el.text).paddingTop || '0');
    // Flipped, the rects come back upside down; measuring from the bottom edge
    // reads them the right way up.
    const position = (rect) => (flipY ? textBox.bottom - rect.bottom : rect.top - textBox.top) - padding;

    const rects = [];
    const walker = document.createTreeWalker(el.text, NodeFilter.SHOW_TEXT);
    const range = document.createRange();
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!node.nodeValue.trim()) continue;
      range.selectNodeContents(node);
      for (const rect of range.getClientRects()) {
        if (rect.height > 0) rects.push({ top: position(rect), height: rect.height });
      }
    }

    // A picture is read as a few lines, so the script doesn't race past it:
    // more for a tall one than a wide one, as on the phone.
    for (const frame of el.text.querySelectorAll('.script-image')) {
      const rect = frame.getBoundingClientRect();
      if (rect.height <= 0) continue;
      const lines = Math.max(2, Math.min(8, Math.round((4 * rect.height) / Math.max(rect.width, 1))));
      const slice = rect.height / lines;
      const top = position(rect);
      for (let i = 0; i < lines; i += 1) rects.push({ top: top + i * slice, height: slice - 0.5 });
    }
    rects.sort((a, b) => a.top - b.top);

    let bottom = -Infinity;
    for (const rect of rects) {
      // A cue is set smaller than the words around it, so two rects on one line
      // have different tops. Overlapping rects are the same line.
      if (rect.top >= bottom - 2) {
        offsets.push(rect.top);
        bottom = rect.top + rect.height;
      } else {
        offsets[offsets.length - 1] = Math.min(offsets[offsets.length - 1], rect.top);
        bottom = Math.max(bottom, rect.top + rect.height);
      }
    }
    run.lineOffsets = offsets;

    // Anchors: each marker's line, then the top and the end of the script.
    const marks = [...el.text.querySelectorAll('.anchor-mark')].map((mark) => {
      const rect = mark.getBoundingClientRect();
      return Math.round(lineForOffset(position(rect) + rect.height / 2 - lineHeight() / 2));
    });
    run.hasAnchors = marks.length > 0;
    const last = Math.max(offsets.length - 1, 0);
    run.anchorLines = [...new Set([0, ...marks, last])].sort((a, b) => a - b);
    updateAnchorButtons();
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

  // The flip is a transform on the scroller, so its own scroll position means
  // what it always does: the script just shows upside down, running down.
  const scrollTopFor = (target) => target;
  const targetForScrollTop = (top) => top;

  // =============================================================================
  // THE CLOCK
  // =============================================================================

  const scrollElapsed = () => Math.max(run.elapsed - run.scrollOrigin, 0);
  const currentLine = () => (scrollElapsed() * settings.linesPerMinute) / 60;

  function applyScroll() {
    const target = Math.min(Math.max(offsetForLine(currentLine()), 0), maxScroll());
    const top = scrollTopFor(target);
    if (Math.abs(el.scroll.scrollTop - top) < 0.5) {
      run.programmaticTop = el.scroll.scrollTop;
      return;
    }
    el.scroll.scrollTop = top;
    run.programmaticTop = el.scroll.scrollTop;
  }

  function updateTimer() {
    const style = timerStyle('teleprompter');
    const duration = timerDuration('teleprompter');

    if (run.countingDown) {
      el.timer.textContent = formatTime(run.countdownValue);
      el.timer.style.color = `var(--color-${style.countdownColor})`;
      return;
    }

    const elapsed = Math.floor(run.elapsed);
    const remaining = duration - elapsed;
    el.timer.textContent = formatTime(duration > 0 ? remaining : elapsed);
    el.timer.style.color = `var(--color-${timerColor(style, remaining, duration)})`;
  }

  let lastAnchorCheck = 0;
  function tick(now) {
    if (run.playing) run.elapsed = run.elapsedAtStart + (performance.now() - run.startedAt) / 1000;
    updateTimer();
    applyScroll();
    if (now - lastAnchorCheck > 250) {
      lastAnchorCheck = now;
      updateAnchorButtons();
    }
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
    track('teleprompter_play');
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
      updateTransport();
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
    track('teleprompter_pause');
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
    track('teleprompter_restart');
    stopCountdown();
    run.playing = false;
    run.hasStarted = false;
    run.elapsed = 0;
    run.scrollOrigin = 0;
    el.scroll.scrollTop = scrollTopFor(0);
    run.programmaticTop = el.scroll.scrollTop;
    updateTransport();
    updateTimer();
    showControls();
    onPlayStateChange?.(false);
  }

  /** During the countdown Play shows the seconds left, in the countdown's
   *  colour, and still pauses while it does. */
  function updateTransport() {
    const running = run.playing || run.countingDown;
    el.playIcon.hidden = running;
    el.pauseIcon.hidden = !running || run.countingDown;
    el.countdown.hidden = !run.countingDown;
    el.play.classList.toggle('is-counting', run.countingDown);
    if (run.countingDown) {
      el.countdown.textContent = String(run.countdownValue);
      el.countdown.style.color = `var(--color-${timerStyle('teleprompter').countdownColor})`;
    }
    el.play.setAttribute('aria-label', run.countingDown ? `Starting in ${run.countdownValue}, Pause` : running ? 'Pause' : 'Play');
    el.play.title = running ? 'Pause (Space)' : 'Play (Space)';
  }

  // =============================================================================
  // ANCHORS
  // =============================================================================

  function anchorTarget(forward) {
    const line = currentLine();
    const lines = run.anchorLines;
    if (forward) return lines.find((l) => l > line + ANCHOR_SLACK) ?? null;
    for (let i = lines.length - 1; i >= 0; i -= 1) if (lines[i] < line - ANCHOR_SLACK) return lines[i];
    return null;
  }

  /** Jump to the next `[anchor]`, or back to the one before. The top and the
   *  end of the script count as anchors. The clock is left where it is. */
  function jumpToAnchor(forward) {
    const target = anchorTarget(forward);
    if (target === null) return;
    trackClick(forward ? 'next_anchor' : 'previous_anchor', 'teleprompter');
    const seconds = settings.linesPerMinute > 0 ? (target * 60) / settings.linesPerMinute : 0;
    run.scrollOrigin = run.elapsed - seconds;
    updateAnchorButtons();
    showControls();
  }

  function updateAnchorButtons() {
    // Kept in the row while there are none, so Play stays in the middle.
    el.prevAnchor.classList.toggle('is-gone', !run.hasAnchors);
    el.nextAnchor.classList.toggle('is-gone', !run.hasAnchors);
    if (!run.hasAnchors) return;
    el.prevAnchor.disabled = anchorTarget(false) === null;
    el.nextAnchor.disabled = anchorTarget(true) === null;
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
  // SCRUBBING, NUDGING AND THE GUIDE
  // =============================================================================

  el.scroll.addEventListener('scroll', () => {
    if (!run.open) return;
    // Ours, not the reader's.
    if (Math.abs(el.scroll.scrollTop - run.programmaticTop) < 1) return;

    // Reading carries on from the line left on the reading line: the script's
    // own position moves, and the talk's clock keeps its own count.
    const line = lineForOffset(targetForScrollTop(el.scroll.scrollTop));
    const target = settings.linesPerMinute > 0 ? (line * 60) / settings.linesPerMinute : 0;
    run.scrollOrigin = run.elapsed - target;
    run.programmaticTop = el.scroll.scrollTop;
    showControls();
  });

  /** Move the script by whole lines, leaving the clock where it is. */
  function nudge(lines) {
    const seconds = settings.linesPerMinute > 0 ? (lines * 60) / settings.linesPerMinute : 0;
    run.scrollOrigin = Math.min(run.scrollOrigin - seconds, run.elapsed);
  }

  /** The guide follows the pointer while it's dragged; the script lines up
   *  with it once it's let go. */
  el.handle.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    el.handle.setPointerCapture(event.pointerId);
    run.dragging = { startY: event.clientY, startTop: run.readingTop };
    root.classList.add('is-dragging-guide');
  });

  el.handle.addEventListener('pointermove', (event) => {
    if (!run.dragging) return;
    const delta = (event.clientY - run.dragging.startY) * (settings.flipsTextVertically ? -1 : 1);
    const [min, max] = readingBounds();
    placeGuide(clamp(run.dragging.startTop + delta, [min, max]));
  });

  const endDrag = (event) => {
    if (!run.dragging) return;
    const delta = (event.clientY - run.dragging.startY) * (settings.flipsTextVertically ? -1 : 1);
    const [min, max] = readingBounds();
    const top = clamp(run.dragging.startTop + delta, [min, max]);
    run.dragging = null;
    root.classList.remove('is-dragging-guide');
    trackClick('reading_guide_drag', 'teleprompter');
    void setSetting('readingGuidePosition', max > min ? (top - min) / (max - min) : 0, { track: false });
    layout();
  };
  el.handle.addEventListener('pointerup', endDrag);
  el.handle.addEventListener('pointercancel', endDrag);

  /** ↑ and ↓ move the guide a line at a time from the keyboard. */
  el.handle.addEventListener('keydown', (event) => {
    if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
    event.preventDefault();
    event.stopPropagation();
    const [min, max] = readingBounds();
    const step = max > min ? lineHeight() / (max - min) : 0;
    const by = (event.key === 'ArrowDown') !== settings.flipsTextVertically ? step : -step;
    void setSetting('readingGuidePosition', clamp(settings.readingGuidePosition + by, [0, 1]), { track: false });
    layout();
  });

  root.addEventListener('mousemove', showControls);
  el.play.addEventListener('click', () => {
    trackClick(run.playing || run.countingDown ? 'pause' : 'play', 'teleprompter');
    togglePlay();
  });
  el.restart.addEventListener('click', () => {
    trackClick('restart', 'teleprompter');
    restart();
  });
  el.back.addEventListener('click', () => {
    trackClick('teleprompter_close', 'teleprompter');
    close();
  });
  el.prevAnchor.addEventListener('click', () => jumpToAnchor(false));
  el.nextAnchor.addEventListener('click', () => jumpToAnchor(true));

  function onKeyDown(event) {
    if (!run.open) return;
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (document.querySelector('.alert-layer, .sheet-layer')) return;
    if (event.target === el.handle && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) return;

    const key = event.key;
    if (key === 'Escape') {
      event.preventDefault();
      close();
    } else if (key === ' ' || key === 'k') {
      event.preventDefault();
      togglePlay();
    } else if (key === 'r' || key === 'R') {
      event.preventDefault();
      restart();
    } else if (key === 'ArrowDown' || key === 'ArrowUp') {
      event.preventDefault();
      nudge(key === 'ArrowDown' ? 1 : -1);
    } else if (key === 'ArrowRight' || key === 'ArrowLeft' || key === 'PageDown' || key === 'PageUp') {
      event.preventDefault();
      jumpToAnchor(key === 'ArrowRight' || key === 'PageDown');
    }
    showControls();
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

    track('teleprompter_started', { word_count: wordCount(text), timer_duration: timerDuration('teleprompter') });

    // The window has to have laid out before lines can be measured.
    requestAnimationFrame(() => {
      render();
      el.scroll.scrollTop = scrollTopFor(0);
      run.programmaticTop = el.scroll.scrollTop;
      updateTimer();
      updateTransport();
      el.scroll.focus({ preventScroll: true });
    });

    startLoop();
  }

  function close() {
    if (!run.open) return;
    track('teleprompter_closed', { elapsed_time: Math.floor(run.elapsed) });
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
      if (fromSlide) run.scrollOrigin = run.elapsed;
      render();
      if (fromSlide) {
        el.scroll.scrollTop = scrollTopFor(0);
        run.programmaticTop = el.scroll.scrollTop;
      }
    },

    /** The script's size, colour, guide or flip changed under it. */
    restyle() {
      if (!run.open) return;
      render();
      updateTimer();
    },
  };
}
