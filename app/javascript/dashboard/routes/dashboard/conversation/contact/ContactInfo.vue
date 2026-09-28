<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { exactTimestamp } from 'shared/helpers/timeHelper';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactInfoRow from './ContactInfoRow.vue';
import Avatar from 'next/avatar/Avatar.vue';
import SocialIcons from './SocialIcons.vue';
import EditContact from './EditContact.vue';
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';
import ContactDeleteModal from 'dashboard/modules/contact/ContactDeleteModal.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';

export default {
  components: {
    NextButton,
    ContactInfoRow,
    EditContact,
    Avatar,
    ComposeConversation,
    SocialIcons,
    ContactMergeModal,
    ContactDeleteModal,
    VoiceCallButton,
    InlineInput,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    showAvatar: {
      type: Boolean,
      default: true,
    },
  },
  emits: ['panelClose'],
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      showEditModal: false,
      isEditingName: false,
      editName: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'contacts/getUIFlags',
      currentChat: 'getSelectedChat',
    }),
    contactProfileLink() {
      return `/app/accounts/${this.$route.params.accountId}/contacts/${this.contact.id}`;
    },
    additionalAttributes() {
      return this.contact.additional_attributes || {};
    },
    location() {
      const {
        country = '',
        city = '',
        country_code: countryCode,
      } = this.additionalAttributes;
      const cityAndCountry = [city, country].filter(item => !!item).join(', ');

      if (!cityAndCountry) {
        return '';
      }
      return this.findCountryFlag(countryCode, cityAndCountry);
    },
    socialProfiles() {
      const {
        social_profiles: socialProfiles,
        screen_name: twitterScreenName,
        social_telegram_user_name: telegramUsername,
      } = this.additionalAttributes;

      const telegram = socialProfiles?.telegram || telegramUsername || '';
      const twitter = socialProfiles?.twitter || twitterScreenName || '';

      return {
        ...(socialProfiles || {}),
        twitter,
        telegram,
      };
    },
  },
  watch: {
    'contact.id': {
      handler(id) {
        this.$store.dispatch('contacts/fetchContactableInbox', id);
      },
      immediate: true,
    },
  },
  methods: {
    exactTimestamp,
    toggleEditModal() {
      this.showEditModal = !this.showEditModal;
    },
    findCountryFlag(countryCode, cityAndCountry) {
      try {
        if (!countryCode) {
          return `${cityAndCountry} 🌎`;
        }

        const code = countryCode?.toLowerCase();
        return `${cityAndCountry} <span class="fi fi-${code} size-3.5"></span>`;
      } catch (error) {
        return '';
      }
    },
    startEditingName() {
      this.editName = this.contact.name || '';
      this.isEditingName = true;
      this.$nextTick(() => {
        this.$refs.nameInput?.focus();
      });
    },
    saveNameEdit() {
      if (!this.isEditingName) return;
      this.isEditingName = false;
      const trimmed = this.editName.trim();
      if (trimmed && trimmed !== this.contact.name) {
        this.updateContactField({ name: trimmed });
      }
    },
    cancelNameEdit() {
      this.isEditingName = false;
    },
    onFieldUpdate(field, value) {
      this.updateContactField({ [field]: value });
    },
    async updateContactField(attrs) {
      const contactId = this.contact.id;
      try {
        await this.$store.dispatch('contacts/update', {
          id: contactId,
          ...attrs,
        });
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
        await this.$store.dispatch('contacts/fetchContactableInbox', contactId);
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          const detail = error.contactErrorDetail;
          if (detail) {
            useAlert(detail);
          } else {
            const invalidAttrs = Array.isArray(error.data) ? error.data : [];
            if (invalidAttrs.includes('email')) {
              useAlert(this.$t('CONTACT_FORM.FORM.EMAIL_ADDRESS.DUPLICATE'));
            } else if (invalidAttrs.includes('phone_number')) {
              useAlert(this.$t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
            } else {
              useAlert(this.$t('CONTACT_FORM.ERROR_MESSAGE'));
            }
          }
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(error.message || this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
      }
    },
  },
};
</script>

<template>
  <div class="w-full text-left rtl:text-right">
    <!-- Header: avatar + name + actions -->
    <div class="flex items-start gap-3 px-4 pt-4 pb-3">
      <Avatar
        v-if="showAvatar"
        :src="contact.thumbnail"
        :name="contact.name"
        :status="contact.availability_status"
        :size="44"
        hide-offline-status
        class="shrink-0"
      />
      <div class="flex-1 min-w-0">
        <!-- Name row -->
        <div class="group/name flex items-center gap-1.5 min-w-0 mb-0.5">
          <InlineInput
            v-if="isEditingName"
            ref="nameInput"
            v-model="editName"
            custom-input-class="!text-sm !font-semibold !w-auto max-w-full [field-sizing:content]"
            class="!w-fit min-w-0"
            @enter-press="saveNameEdit"
            @escape-press="cancelNameEdit"
            @blur="saveNameEdit"
          />
          <h3
            v-else
            class="text-sm font-semibold text-n-slate-12 truncate cursor-pointer hover:text-n-slate-11 transition-colors my-0"
            :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
            @click="startEditingName"
          >
            {{ contact.name }}
          </h3>
          <NextButton
            ghost
            xs
            slate
            icon="i-lucide-pencil"
            :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
            class="shrink-0 opacity-0 transition-opacity"
            :class="isEditingName ? 'invisible' : 'group-hover/name:opacity-100 focus-visible:opacity-100'"
            @click="startEditingName"
          />
        </div>
        <!-- Meta: created_at + profile link -->
        <div class="flex items-center gap-2">
          <span
            v-if="contact.created_at"
            v-tooltip.right="
              `${$t('CONTACT_PANEL.CREATED_AT_LABEL')} ${exactTimestamp(contact.created_at)}`
            "
            class="i-lucide-info w-3.5 h-3.5 text-n-slate-10"
          />
          <a
            :href="contactProfileLink"
            target="_blank"
            rel="noopener nofollow noreferrer"
          >
            <span class="i-lucide-external-link w-3.5 h-3.5 text-n-slate-10 hover:text-n-brand transition-colors" />
          </a>
        </div>
      </div>
    </div>

    <!-- Description -->
    <p
      v-if="additionalAttributes.description"
      class="px-4 text-xs text-n-slate-11 break-words mb-2"
    >
      {{ additionalAttributes.description }}
    </p>

    <!-- Divider -->
    <div class="h-px bg-n-weak mx-4 mb-3" />

    <!-- Info rows -->
    <div class="flex flex-col gap-1 px-4 pb-3">
      <ContactInfoRow
        :href="contact.email ? `mailto:${contact.email}` : ''"
        :value="contact.email"
        icon="mail"
        emoji="✉️"
        :title="$t('CONTACT_PANEL.EMAIL_ADDRESS')"
        show-copy
        editable
        @update="value => onFieldUpdate('email', value)"
      />
      <ContactInfoRow
        :href="contact.phone_number ? `tel:${contact.phone_number}` : ''"
        :value="contact.phone_number"
        icon="call"
        emoji="📞"
        :title="$t('CONTACT_PANEL.PHONE_NUMBER')"
        show-copy
        editable
        @update="value => onFieldUpdate('phone_number', value)"
      />
      <ContactInfoRow
        v-if="contact.identifier"
        :value="contact.identifier"
        icon="contact-identify"
        emoji="🪪"
        :title="$t('CONTACT_PANEL.IDENTIFIER')"
      />
      <ContactInfoRow
        :value="additionalAttributes.company_name"
        icon="building-bank"
        emoji="🏢"
        :title="$t('CONTACT_PANEL.COMPANY')"
        editable
        @update="
          value =>
            updateContactField({
              additional_attributes: {
                ...additionalAttributes,
                company_name: value,
              },
            })
        "
      />
      <ContactInfoRow
        v-if="location || additionalAttributes.location"
        :value="location || additionalAttributes.location"
        icon="map"
        emoji="🌍"
        :title="$t('CONTACT_PANEL.LOCATION')"
      />
      <SocialIcons :social-profiles="socialProfiles" />
    </div>

    <!-- Action buttons -->
    <div class="flex items-center gap-1 px-4 pb-4">
      <ComposeConversation :contact-id="String(contact.id)">
        <template #trigger>
          <NextButton
            v-tooltip.top="$t('CONTACT_PANEL.NEW_MESSAGE')"
            icon="i-ph-chat-circle-dots"
            slate
            faded
            sm
          />
        </template>
      </ComposeConversation>
      <VoiceCallButton
        :phone="contact.phone_number"
        :contact-id="contact.id"
        :conversation-id="currentChat?.id"
        icon="i-lucide-phone"
        sm
        faded
        slate
        :tooltip-label="$t('CONTACT_PANEL.CALL')"
      />
      <NextButton
        v-tooltip.top="$t('EDIT_CONTACT.BUTTON_LABEL')"
        icon="i-ph-pencil-simple"
        slate
        faded
        sm
        @click="toggleEditModal"
      />
      <ContactMergeModal :primary-contact="contact">
        <template #trigger>
          <NextButton
            v-tooltip.top="$t('CONTACT_PANEL.MERGE_CONTACT')"
            icon="i-ph-arrows-merge"
            slate
            faded
            sm
            :disabled="uiFlags.isMerging"
          />
        </template>
      </ContactMergeModal>
      <ContactDeleteModal
        v-if="isAdmin"
        :contact="contact"
        @deleted="$emit('panelClose')"
      >
        <template #trigger>
          <NextButton
            v-tooltip.top="$t('DELETE_CONTACT.BUTTON_LABEL')"
            icon="i-ph-trash"
            slate
            faded
            sm
            ruby
            :disabled="uiFlags.isDeleting"
          />
        </template>
      </ContactDeleteModal>
    </div>

    <EditContact
      :show="showEditModal"
      :contact="contact"
      @cancel="toggleEditModal"
    />
  </div>
</template>
