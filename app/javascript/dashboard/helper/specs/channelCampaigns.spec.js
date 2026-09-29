import { describe, expect, it } from 'vitest';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import {
  CHANNEL_CAMPAIGN_KINDS,
  CHANNEL_CAMPAIGN_TYPES,
  getCampaignAnalyticsRouteName,
  getChannelTypesForKind,
  getKindForChannelType,
  isChannelCampaignInbox,
} from '../channelCampaigns';

describe('channelCampaigns', () => {
  describe('isChannelCampaignInbox', () => {
    it.each([
      INBOX_TYPES.EMAIL,
      INBOX_TYPES.TELEGRAM,
      INBOX_TYPES.INSTAGRAM,
      INBOX_TYPES.FB,
      INBOX_TYPES.LINE,
      INBOX_TYPES.TIKTOK,
      INBOX_TYPES.API,
    ])('atende %s pelo disparo generico', channelType => {
      expect(isChannelCampaignInbox(channelType)).toBe(true);
    });

    // SMS, Twilio e WhatsApp seguem nas telas e nos servicos proprios do upstream; Website e
    // campanha "ongoing" do widget.
    it.each([
      INBOX_TYPES.SMS,
      INBOX_TYPES.TWILIO,
      INBOX_TYPES.WHATSAPP,
      INBOX_TYPES.WEB,
      INBOX_TYPES.TWITTER,
      undefined,
    ])('nao atende %s', channelType => {
      expect(isChannelCampaignInbox(channelType)).toBe(false);
    });
  });

  it('as duas abas cobrem exatamente os canais do disparo generico, sem repetir', () => {
    const covered = [
      ...getChannelTypesForKind(CHANNEL_CAMPAIGN_KINDS.EMAIL),
      ...getChannelTypesForKind(CHANNEL_CAMPAIGN_KINDS.CHANNELS),
    ];

    expect(covered).toHaveLength(CHANNEL_CAMPAIGN_TYPES.length);
    expect(new Set(covered)).toEqual(new Set(CHANNEL_CAMPAIGN_TYPES));
  });

  it('e-mail tem aba propria', () => {
    expect(getChannelTypesForKind(CHANNEL_CAMPAIGN_KINDS.EMAIL)).toEqual([
      INBOX_TYPES.EMAIL,
    ]);
    expect(getKindForChannelType(INBOX_TYPES.EMAIL)).toBe(
      CHANNEL_CAMPAIGN_KINDS.EMAIL
    );
  });

  it('as demais caixas ficam em Outros canais', () => {
    expect(getKindForChannelType(INBOX_TYPES.TELEGRAM)).toBe(
      CHANNEL_CAMPAIGN_KINDS.CHANNELS
    );
    expect(
      getChannelTypesForKind(CHANNEL_CAMPAIGN_KINDS.CHANNELS)
    ).not.toContain(INBOX_TYPES.EMAIL);
  });

  describe('getCampaignAnalyticsRouteName', () => {
    it('leva cada campanha para a tela do seu tipo', () => {
      expect(getCampaignAnalyticsRouteName(INBOX_TYPES.WHATSAPP)).toBe(
        'campaigns_whatsapp_analytics'
      );
      expect(getCampaignAnalyticsRouteName(INBOX_TYPES.EMAIL)).toBe(
        'campaigns_email_analytics'
      );
      expect(getCampaignAnalyticsRouteName(INBOX_TYPES.TELEGRAM)).toBe(
        'campaigns_channels_analytics'
      );
    });
  });
});
