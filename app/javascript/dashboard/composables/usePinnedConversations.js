// [FORK] Fixar conversas no topo — persistido em localStorage
import { ref } from 'vue';

const STORAGE_KEY = 'pinned_conversation_ids';

function load() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
  } catch {
    return [];
  }
}

// Shared reactive state so all components see the same pins
const pinnedIds = ref(load());

export function usePinnedConversations() {
  const isPinned = id => pinnedIds.value.includes(id);

  const togglePin = id => {
    pinnedIds.value = isPinned(id)
      ? pinnedIds.value.filter(x => x !== id)
      : [...pinnedIds.value, id];
    localStorage.setItem(STORAGE_KEY, JSON.stringify(pinnedIds.value));
  };

  return { pinnedIds, isPinned, togglePin };
}
