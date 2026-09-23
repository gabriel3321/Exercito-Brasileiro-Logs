import { EmbedBuilder } from 'discord.js';
import { cleanText, discordTimestamp } from './text.js';

const TITLES = {
  JOIN: '🟢 JOGADOR ENTROU',
  LEAVE: '🔴 JOGADOR SAIU',
  WARN: '⚠️ ADVERTÊNCIA',
  KICK: '🥾 EXPULSÃO',
  MUTE: '🔇 MUTE',
  UNMUTE: '🔊 UNMUTE',
  TEMPBAN: '⏳ TEMPBAN',
  BAN: '🚨 BANIMENTO',
  UNBAN: '✅ UNBAN',
  CARGO: '🎖️ CARGO ALTERADO',
  COMANDO: '🛠️ COMANDO ADMIN',
  ANTICHEAT_SUSPECT: '🛡️ ANTICHEAT • SUSPEITA',
  ANTICHEAT_BAN: '🛡️ ANTICHEAT • BAN AUTOMÁTICO',
};

function field(name, value, inline = false) {
  return { name, value: cleanText(value, 1024), inline };
}

export function buildLogEmbed(log) {
  const action = String(log.action || 'LOG').toUpperCase();
  const embed = new EmbedBuilder()
    .setTitle(TITLES[action] || `📋 ${cleanText(action, 120)}`)
    .setTimestamp(new Date((Number(log.timestamp) || Date.now() / 1000) * 1000))
    .setFooter({ text: `EB Logs • ${cleanText(log.id || 'sem-id', 80)}` });

  if (log.admin) {
    embed.addFields(field(
      'Administrador',
      `${cleanText(log.admin.displayName || log.admin.username)}\n@${cleanText(log.admin.username)}\nUserId: ${Number(log.admin.userId) || 0}\nCargo: ${cleanText(log.admin.rank || 'Nenhum')}`,
      true,
    ));
  }

  if (log.target) {
    embed.addFields(field(
      'Alvo',
      `${cleanText(log.target.displayName || log.target.username || log.target.name)}\n@${cleanText(log.target.username || log.target.name)}\nUserId: ${Number(log.target.userId) || 0}`,
      true,
    ));
  }

  if (log.reason) embed.addFields(field('Motivo', log.reason));
  if (log.detail) embed.addFields(field('Detalhes', log.detail));

  if (log.extra && typeof log.extra === 'object' && Object.keys(log.extra).length) {
    const lines = Object.entries(log.extra).slice(0, 12).map(([k, v]) => `${k}: ${cleanText(v, 180)}`);
    embed.addFields(field('Dados', lines.join('\n')));
  }

  if (log.server) {
    embed.addFields(field(
      'Servidor Roblox',
      `JobId: ${cleanText(log.server.jobId || '-')}\nPlaceId: ${Number(log.server.placeId) || 0}\nJogadores: ${Number(log.server.playerCount) || 0}`,
    ));
  }

  embed.addFields(field('Horário', discordTimestamp(log.timestamp)));
  return embed;
}
