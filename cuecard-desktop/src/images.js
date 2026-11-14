/**
 * The images placed in scripts, as the phone app keeps them: one file each in
 * the app's own storage, named for what's in it, so the same picture added
 * twice is only kept once. A script holds `[image name]` where it goes.
 *
 * Photos are kept as JPEG and anything with see-through parts as PNG, no
 * bigger than 2048 pixels on their longest side, turned upright.
 */

import { imagesList, imagesRead, imagesRemove, imagesSave } from './tauri.js';

/** The longest side an image is kept at. */
export const MAX_PIXEL_SIZE = 2048;

const NAME = /^[A-Za-z0-9-]+\.[A-Za-z0-9]+$/;
export const isImageName = (name) => NAME.test(String(name || ''));

const TYPES = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp' };
const typeOf = (name) => TYPES[name.split('.').pop().toLowerCase()] || 'application/octet-stream';

/** name → object URL, or null once it's known not to be kept here. */
const urls = new Map();
const loading = new Map();
const listeners = new Set();

/** Called with a name whenever an image arrives, for whoever drew a gap for it. */
export function onImageLoaded(fn) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

/** Where other places can look for an image this device doesn't have, such as
 *  the storage folder. Returns its bytes, or null. */
let fallback = null;
export function setImageFallback(fn) {
  fallback = fn;
}

/** The image's URL if it's already loaded; undefined if not asked for yet. */
export const cachedImageURL = (name) => urls.get(name);

/** The image's URL, loading it if need be. Null if it can't be found. */
export function imageURL(name) {
  if (!isImageName(name)) return Promise.resolve(null);
  if (urls.has(name)) return Promise.resolve(urls.get(name));
  if (loading.has(name)) return loading.get(name);

  const promise = (async () => {
    let bytes = await imagesRead(name);
    if (!bytes && fallback) {
      bytes = await fallback(name);
      if (bytes) await imagesSave(name, bytes).catch(() => {});
    }
    const url = bytes ? URL.createObjectURL(new Blob([bytes], { type: typeOf(name) })) : null;
    urls.set(name, url);
    loading.delete(name);
    if (url) listeners.forEach((fn) => fn(name));
    return url;
  })();
  loading.set(name, promise);
  return promise;
}

/** Forget that an image was missing, so the next look tries again. */
export function retryMissing() {
  for (const [name, url] of urls) if (url === null) urls.delete(name);
}

/** An image's bytes from the store, or null. */
export const imageBytes = (name) => (isImageName(name) ? imagesRead(name) : Promise.resolve(null));

/** Keep bytes that already have their name, as from the storage folder. */
export async function keepImage(name, bytes) {
  if (!isImageName(name)) return false;
  try {
    await imagesSave(name, bytes);
    if (urls.get(name) === null) urls.delete(name);
    return true;
  } catch {
    return false;
  }
}

// =============================================================================
// ADDING
// =============================================================================

async function decode(blob) {
  try {
    return await createImageBitmap(blob, { imageOrientation: 'from-image' });
  } catch {
    // Formats the bitmap decoder doesn't take may still load as an <img>.
    const url = URL.createObjectURL(blob);
    try {
      const img = new Image();
      img.src = url;
      await img.decode();
      return img;
    } finally {
      URL.revokeObjectURL(url);
    }
  }
}

/** Whether any pixel lets what's behind it show through. */
function hasAlpha(context, width, height) {
  const data = context.getImageData(0, 0, width, height).data;
  for (let i = 3; i < data.length; i += 4) if (data[i] < 255) return true;
  return false;
}

const toBlob = (canvas, type, quality) =>
  new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Encode failed'))), type, quality));

/**
 * Keep a picture, scaled down and turned upright, and return its name. Null if
 * it isn't an image or couldn't be kept.
 */
export async function addImage(blob) {
  try {
    const source = await decode(blob);
    const width = source.width || source.naturalWidth;
    const height = source.height || source.naturalHeight;
    if (!width || !height) return null;

    const scale = Math.min(1, MAX_PIXEL_SIZE / Math.max(width, height));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(width * scale));
    canvas.height = Math.max(1, Math.round(height * scale));
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(source, 0, 0, canvas.width, canvas.height);
    source.close?.();

    // Only a format that can be see-through needs looking at.
    const mayHaveAlpha = !/jpe?g/i.test(blob.type);
    const isPNG = mayHaveAlpha && hasAlpha(context, canvas.width, canvas.height);
    const encoded = await toBlob(canvas, isPNG ? 'image/png' : 'image/jpeg', 0.85);
    const bytes = new Uint8Array(await encoded.arrayBuffer());

    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    const name = `${[...hash.slice(0, 16)].map((b) => b.toString(16).padStart(2, '0')).join('')}.${isPNG ? 'png' : 'jpg'}`;

    await imagesSave(name, bytes);
    if (!urls.get(name)) urls.set(name, URL.createObjectURL(new Blob([bytes], { type: typeOf(name) })));
    return name;
  } catch (error) {
    console.error('Error adding an image:', error);
    return null;
  }
}

/** The image files among what was pasted or dropped. */
export function imageFiles(dataTransfer) {
  if (!dataTransfer) return [];
  const files = [...(dataTransfer.files || [])].filter((file) => file.type.startsWith('image/'));
  if (files.length) return files;
  return [...(dataTransfer.items || [])]
    .filter((item) => item.kind === 'file' && item.type.startsWith('image/'))
    .map((item) => item.getAsFile())
    .filter(Boolean);
}

// =============================================================================
// DRAWING
// =============================================================================

/**
 * Fill every `img[data-image]` in a tree with its picture. One that can't be
 * found is drawn as an empty frame. `onLoad` runs as each one finishes, for
 * anything laid out around their size.
 */
export function hydrateImages(root, onLoad) {
  for (const img of root.querySelectorAll('img[data-image]')) {
    if (img.dataset.hydrated) continue;
    img.dataset.hydrated = '1';
    const name = img.dataset.image;
    const frame = img.closest('.script-image') || img.parentElement;

    const show = (url) => {
      if (url) {
        if (onLoad) img.addEventListener('load', () => onLoad(img), { once: true });
        img.src = url;
        frame?.classList.remove('is-missing');
      } else {
        frame?.classList.add('is-missing');
        onLoad?.(img);
      }
    };

    const cached = urls.get(name);
    if (cached !== undefined) show(cached);
    else void imageURL(name).then(show);
  }
}

// =============================================================================
// TIDYING
// =============================================================================

/**
 * Delete every image no script places any more. One added in the last day is
 * kept whatever, so one placed while this runs is never caught by it.
 */
export async function removeUnusedImages(keeping) {
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
  for (const image of await imagesList()) {
    if (keeping.has(image.name)) continue;
    if ((image.modified ?? 0) >= cutoff) continue;
    await imagesRemove(image.name);
    const url = urls.get(image.name);
    if (url) URL.revokeObjectURL(url);
    urls.delete(image.name);
  }
}
