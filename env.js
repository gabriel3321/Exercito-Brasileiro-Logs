import 'dotenv/config';

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Variável obrigatória ausente: ${name}`);
  return value;
}

function numberEnv(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
}

export const env = Object.freeze({
  discordToken: required('DISCORD_TOKEN'),
  discordClientId: required('DISCORD_CLIENT_ID'),
  discordGuildId: process.env.DISCORD_GUILD_ID?.trim() || null,

  channels: Object.freeze({
    general: process.env.LOG_GENERAL_CHANNEL_ID?.trim() || null,
    admin: process.env.LOG_ADMIN_CHANNEL_ID?.trim() || null,
    punishments: process.env.LOG_PUNISHMENTS_CHANNEL_ID?.trim() || null,
    anticheat: process.env.LOG_ANTICHEAT_CHANNEL_ID?.trim() || null,
    ranks: process.env.LOG_RANKS_CHANNEL_ID?.trim() || null,
  }),

  robloxSharedSecret: required('ROBLOX_SHARED_SECRET'),
  port: numberEnv('PORT', 3000),
  dataDir: process.env.DATA_DIR?.trim() || './data',
  publicBaseUrl: process.env.PUBLIC_BASE_URL?.trim() || null,

  authMaxSkewSeconds: numberEnv('ROBLOX_AUTH_MAX_SKEW_SECONDS', 120),
  activeServerTimeoutSeconds: numberEnv('ACTIVE_SERVER_TIMEOUT_SECONDS', 75),
  logRetentionDays: numberEnv('LOG_RETENTION_DAYS', 7),
  maxRecentLogsInMemory: numberEnv('MAX_RECENT_LOGS_IN_MEMORY', 5000),
});
