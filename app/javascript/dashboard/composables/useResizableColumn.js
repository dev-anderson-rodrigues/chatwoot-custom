import { ref, onUnmounted } from 'vue';

/**
 * Composable that makes a column resizable via a drag handle.
 * Width is persisted in localStorage and clamped between min and max.
 * Double-clicking the handle resets to the default width.
 *
 * @param {object} [options]
 * @param {string} [options.storageKey='chat_list_column_width']
 * @param {number} [options.defaultWidth=340]
 * @param {number} [options.minWidth=280]
 * @param {number} [options.maxWidth=600]
 * @param {'right'|'left'} [options.direction='right'] - side the handle is on;
 *   'left' inverts the delta (drag left = grow, drag right = shrink).
 */
export function useResizableColumn({
  storageKey = 'chat_list_column_width',
  defaultWidth = 340,
  minWidth = 280,
  maxWidth = 600,
  direction = 'right',
} = {}) {
  const storedWidth = parseInt(localStorage.getItem(storageKey), 10);
  const width = ref(
    !isNaN(storedWidth)
      ? Math.min(maxWidth, Math.max(minWidth, storedWidth))
      : defaultWidth
  );

  let startX = 0;
  let startWidth = 0;
  let isDragging = false;

  const onMouseMove = event => {
    if (!isDragging) return;
    const rawDelta = event.clientX - startX;
    const delta = direction === 'left' ? -rawDelta : rawDelta;
    width.value = Math.min(maxWidth, Math.max(minWidth, startWidth + delta));
  };

  const onMouseUp = () => {
    if (!isDragging) return;
    isDragging = false;
    localStorage.setItem(storageKey, String(width.value));
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
    document.removeEventListener('mousemove', onMouseMove);
    document.removeEventListener('mouseup', onMouseUp);
  };

  const onHandleMouseDown = event => {
    event.preventDefault();
    isDragging = true;
    startX = event.clientX;
    startWidth = width.value;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
  };

  const onHandleDblClick = () => {
    width.value = defaultWidth;
    localStorage.removeItem(storageKey);
  };

  onUnmounted(() => {
    document.removeEventListener('mousemove', onMouseMove);
    document.removeEventListener('mouseup', onMouseUp);
  });

  return {
    columnWidth: width,
    onHandleMouseDown,
    onHandleDblClick,
  };
}
