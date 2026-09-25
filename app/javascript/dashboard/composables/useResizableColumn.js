import { ref, onUnmounted } from 'vue';

const STORAGE_KEY = 'chat_list_column_width';
const DEFAULT_WIDTH = 340;
const MIN_WIDTH = 280;
const MAX_WIDTH = 600;

/**
 * Composable that makes a column resizable via a drag handle.
 * Width is persisted in localStorage and clamped between MIN and MAX.
 * Double-clicking the handle resets to the default width.
 */
export function useResizableColumn() {
  const storedWidth = parseInt(localStorage.getItem(STORAGE_KEY), 10);
  const width = ref(
    !isNaN(storedWidth) ? Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, storedWidth)) : DEFAULT_WIDTH
  );

  let startX = 0;
  let startWidth = 0;
  let isDragging = false;

  const onMouseMove = event => {
    if (!isDragging) return;
    const delta = event.clientX - startX;
    const newWidth = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, startWidth + delta));
    width.value = newWidth;
  };

  const onMouseUp = () => {
    if (!isDragging) return;
    isDragging = false;
    localStorage.setItem(STORAGE_KEY, String(width.value));
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
    width.value = DEFAULT_WIDTH;
    localStorage.removeItem(STORAGE_KEY);
  };

  onUnmounted(() => {
    document.removeEventListener('mousemove', onMouseMove);
    document.removeEventListener('mouseup', onMouseUp);
  });

  return {
    columnWidth: width,
    onHandleMouseDown,
    onHandleDblClick,
    DEFAULT_WIDTH,
    MIN_WIDTH,
    MAX_WIDTH,
  };
}
