<script setup>
import { computed } from 'vue';
import ContactPanel from 'dashboard/routes/dashboard/conversation/ContactPanel.vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useWindowSize } from '@vueuse/core';
import { vOnClickOutside } from '@vueuse/components';
import wootConstants from 'dashboard/constants/globals';
import { useResizableColumn } from 'dashboard/composables/useResizableColumn';

defineProps({
  currentChat: {
    required: true,
    type: Object,
  },
});

const { uiSettings, updateUISettings } = useUISettings();
const { width: windowWidth } = useWindowSize();

// [FORK] Sidebar da conversa redimensionável
const { columnWidth: sidebarWidth, onHandleMouseDown, onHandleDblClick } =
  useResizableColumn({
    storageKey: 'conversation_sidebar_width',
    defaultWidth: 320,
    minWidth: 240,
    maxWidth: 520,
    direction: 'left',
  });

const sidebarStyle = computed(() =>
  windowWidth.value >= wootConstants.SMALL_SCREEN_BREAKPOINT
    ? { width: `${sidebarWidth.value}px`, minWidth: `${sidebarWidth.value}px` }
    : {}
);

const activeTab = computed(() => {
  const { is_contact_sidebar_open: isContactSidebarOpen } = uiSettings.value;

  if (isContactSidebarOpen) {
    return 0;
  }
  return null;
});

const isSmallScreen = computed(
  () => windowWidth.value < wootConstants.SMALL_SCREEN_BREAKPOINT
);

const closeContactPanel = () => {
  if (isSmallScreen.value && uiSettings.value?.is_contact_sidebar_open) {
    updateUISettings({
      is_contact_sidebar_open: false,
      is_copilot_panel_open: false,
    });
  }
};
</script>

<template>
  <div
    v-on-click-outside="[
      () => closeContactPanel(),
      {
        ignore: [
          'dialog.ProseMirror-prompt-backdrop',
          '[data-popover-content]',
          '[data-popover-backdrop]',
        ],
      },
    ]"
    class="relative bg-n-surface-2 h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static ltr:border-l rtl:border-r border-n-weak shadow-lg md:shadow-none"
    :class="[
      {
        'md:flex': activeTab === 0,
        'md:hidden': activeTab !== 0,
      },
    ]"
    :style="sidebarStyle"
  >
    <!-- [FORK] Handle de redimensionamento do painel lateral -->
    <div
      class="absolute top-0 bottom-0 ltr:left-0 rtl:right-0 w-1 cursor-col-resize z-20 hover:bg-n-brand/30 transition-colors hidden md:block"
      @mousedown="onHandleMouseDown"
      @dblclick="onHandleDblClick"
    />
    <div class="flex flex-1 overflow-auto">
      <ContactPanel
        v-show="activeTab === 0"
        :conversation-id="currentChat.id"
        :inbox-id="currentChat.inbox_id"
      />
    </div>
  </div>
</template>
