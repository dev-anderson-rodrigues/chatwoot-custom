import { computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';

// Palette of distinguishable colors for agent message bubbles
export const MESSAGE_COLOR_PALETTE = [
  '#7C3AED', // violet
  '#2563EB', // blue
  '#059669', // emerald
  '#D97706', // amber
  '#DC2626', // red
  '#0891B2', // cyan
  '#BE185D', // pink
  '#65A30D', // lime
  '#9333EA', // purple
  '#C2410C', // orange
];

/**
 * Returns '#ffffff' or '#000000' depending on the background luminance,
 * so text always has sufficient contrast (WCAG-based).
 * @param {string} hexColor - hex color string like '#7C3AED'
 * @returns {string}
 */
export function contrastColor(hexColor) {
  if (!hexColor) return '#000000';
  const hex = hexColor.replace('#', '');
  if (hex.length !== 6) return '#000000';
  const r = parseInt(hex.slice(0, 2), 16);
  const g = parseInt(hex.slice(2, 4), 16);
  const b = parseInt(hex.slice(4, 6), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > 0.5 ? '#000000' : '#ffffff';
}

/**
 * Composable for per-agent message bubble colors.
 * Colors are stored client-side in ui_settings.message_colors without backend changes.
 *
 * Usage:
 *   const { getColorForAgent, setColorForAgent } = useMessageColors();
 *   const color = getColorForAgent(agentId);
 */
export function useMessageColors() {
  const { uiSettings, updateUISettings } = useUISettings();

  /** The full color map: { [agentId: string]: hex } */
  const messageColors = computed(() => uiSettings.value.message_colors || {});

  /**
   * Returns the assigned color for an agent, or null if not set.
   * @param {number|string} agentId
   * @returns {string|null}
   */
  const getColorForAgent = agentId => {
    if (!agentId) return null;
    return messageColors.value[String(agentId)] || null;
  };

  /**
   * Persists a color assignment for an agent.
   * @param {number|string} agentId
   * @param {string} color - hex color string
   */
  const setColorForAgent = (agentId, color) => {
    updateUISettings({
      message_colors: {
        ...messageColors.value,
        [String(agentId)]: color,
      },
    });
  };

  /**
   * Removes the color assignment for an agent (resets to default).
   * @param {number|string} agentId
   */
  const clearColorForAgent = agentId => {
    const updated = { ...messageColors.value };
    delete updated[String(agentId)];
    updateUISettings({ message_colors: updated });
  };

  /**
   * Returns a palette color at position index (wraps around).
   * Useful to auto-assign colors on first use.
   * @param {number} index
   * @returns {string}
   */
  const getPaletteColor = index =>
    MESSAGE_COLOR_PALETTE[index % MESSAGE_COLOR_PALETTE.length];

  return {
    messageColors,
    getColorForAgent,
    setColorForAgent,
    clearColorForAgent,
    getPaletteColor,
    contrastColor,
    MESSAGE_COLOR_PALETTE,
  };
}
