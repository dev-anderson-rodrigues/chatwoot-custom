// [FORK] Campanhas de disparo em massa por qualquer caixa (Onda 7 / fatia 2).
//
// Lado do front do que o servico generico do backend atende
// (Custom::Campaign::GENERIC_INBOX_TYPES). SMS, Twilio SMS e WhatsApp continuam nas telas
// e nos servicos proprios do upstream.
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const EMAIL_CAMPAIGN_CHANNEL_TYPES = [INBOX_TYPES.EMAIL];

// So alcançam quem ja escreveu naquela caixa (o backend pula os demais com o motivo).
export const OTHER_CAMPAIGN_CHANNEL_TYPES = [
  INBOX_TYPES.TELEGRAM,
  INBOX_TYPES.INSTAGRAM,
  INBOX_TYPES.FB,
  INBOX_TYPES.LINE,
  INBOX_TYPES.TIKTOK,
  INBOX_TYPES.API,
];

export const CHANNEL_CAMPAIGN_TYPES = [
  ...EMAIL_CAMPAIGN_CHANNEL_TYPES,
  ...OTHER_CAMPAIGN_CHANNEL_TYPES,
];

// Nomes de marca, nao traduzidos.
export const CHANNEL_CAMPAIGN_LABELS = {
  [INBOX_TYPES.TELEGRAM]: 'Telegram',
  [INBOX_TYPES.INSTAGRAM]: 'Instagram',
  [INBOX_TYPES.FB]: 'Facebook',
  [INBOX_TYPES.LINE]: 'LINE',
  [INBOX_TYPES.TIKTOK]: 'TikTok',
  [INBOX_TYPES.API]: 'API',
};

export const CHANNEL_CAMPAIGN_KINDS = {
  EMAIL: 'email',
  CHANNELS: 'channels',
};

export const isChannelCampaignInbox = channelType =>
  CHANNEL_CAMPAIGN_TYPES.includes(channelType);

export const getChannelTypesForKind = kind =>
  kind === CHANNEL_CAMPAIGN_KINDS.EMAIL
    ? EMAIL_CAMPAIGN_CHANNEL_TYPES
    : OTHER_CAMPAIGN_CHANNEL_TYPES;

export const getKindForChannelType = channelType =>
  EMAIL_CAMPAIGN_CHANNEL_TYPES.includes(channelType)
    ? CHANNEL_CAMPAIGN_KINDS.EMAIL
    : CHANNEL_CAMPAIGN_KINDS.CHANNELS;

// Onde fica a tela de analytics de cada campanha.
export const getCampaignAnalyticsRouteName = channelType => {
  if (channelType === INBOX_TYPES.WHATSAPP)
    return 'campaigns_whatsapp_analytics';

  return getKindForChannelType(channelType) === CHANNEL_CAMPAIGN_KINDS.EMAIL
    ? 'campaigns_email_analytics'
    : 'campaigns_channels_analytics';
};
