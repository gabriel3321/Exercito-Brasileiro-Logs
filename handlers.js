import { EmbedBuilder } from 'discord.js';
import { serverRegistry } from '../services/serverRegistry.js';
import { logStore } from '../services/logStore.js';
import { humanUptime, cleanText } from '../utils/text.js';

function base(title) {
  return new EmbedBuilder().setTitle(title).setTimestamp();
}

export async function handleInteraction(interaction) {
  if (!interaction.isChatInputCommand()) return;
  await interaction.deferReply({ ephemeral: true });

  if (interaction.commandName === 'help') {
    const embed = base('🛡️ EB Logs • Comandos').setDescription([
      '`/log ativos` — jogadores online',
      '`/log status` — status da integração',
      '`/log ultimos` — logs recentes',
      '`/player info` — procura jogador online',
      '`/server ativos` — servidores Roblox ativos',
    ].join('\n'));
    return interaction.editReply({ embeds: [embed] });
  }

  if (interaction.commandName === 'log') {
    const sub = interaction.options.getSubcommand();
    if (sub === 'ativos') {
      const servers = serverRegistry.getServers();
      const total = servers.reduce((n, s) => n + s.playerCount, 0);
      const lines = [];
      for (const [i, server] of servers.slice(0, 12).entries()) {
        lines.push(`**Servidor ${i + 1}** • ${server.playerCount} jogador(es)`);
        for (const p of server.players.slice(0, 8)) lines.push(`↳ ${cleanText(p.displayName, 40)} (@${cleanText(p.username, 40)}) • ${p.rank}`);
        if (server.players.length > 8) lines.push(`↳ +${server.players.length - 8} jogador(es)`);
      }
      const embed = base('🟢 JOGADORES ONLINE').setDescription(cleanText(lines.join('\n') || 'Nenhum servidor ativo detectado.', 3900)).addFields({ name: 'Total', value: String(total), inline: true }, { name: 'Servidores', value: String(servers.length), inline: true });
      return interaction.editReply({ embeds: [embed] });
    }

    if (sub === 'status') {
      const stats = serverRegistry.stats();
      const embed = base('📡 STATUS ROBLOX ↔ BOT').addFields(
        { name: 'Bot', value: '🟢 Online', inline: true },
        { name: 'Servidores ativos', value: String(stats.servers), inline: true },
        { name: 'Jogadores online', value: String(stats.players), inline: true },
        { name: 'Logs armazenados', value: String(logStore.size()), inline: true },
        { name: 'Uptime', value: humanUptime(process.uptime()), inline: true },
      );
      return interaction.editReply({ embeds: [embed] });
    }

    if (sub === 'ultimos') {
      const n = interaction.options.getInteger('quantidade') || 8;
      const logs = logStore.getRecent(n);
      const lines = logs.map((x) => {
        const who = x.target?.username || x.target?.name || x.target?.userId || '-';
        return `• <t:${Math.floor(x.timestamp)}:R> **${cleanText(x.action, 32)}** → ${cleanText(who, 40)}${x.reason ? ` • ${cleanText(x.reason, 80)}` : ''}`;
      });
      return interaction.editReply({ embeds: [base('📋 LOGS RECENTES').setDescription(lines.join('\n') || 'Nenhum log recebido ainda.')] });
    }
  }

  if (interaction.commandName === 'player' && interaction.options.getSubcommand() === 'info') {
    const query = interaction.options.getString('busca', true);
    const results = serverRegistry.findPlayer(query).slice(0, 10);
    const lines = results.map((p) => `**${cleanText(p.displayName, 60)}** (@${cleanText(p.username, 40)})\nUserId: ${p.userId} • Cargo: ${p.rank}\nServidor: \`${cleanText(p.jobId, 50)}\``);
    return interaction.editReply({ embeds: [base('👤 PLAYER INFO').setDescription(lines.join('\n\n') || 'Jogador não encontrado entre os usuários online.')] });
  }

  if (interaction.commandName === 'server' && interaction.options.getSubcommand() === 'ativos') {
    const servers = serverRegistry.getServers();
    const lines = servers.slice(0, 15).map((s, i) => `**${i + 1}.** ${s.playerCount} jogador(es) • PlaceId ${s.placeId}\n\`${cleanText(s.jobId, 70)}\``);
    return interaction.editReply({ embeds: [base('🖥️ SERVIDORES ATIVOS').setDescription(cleanText(lines.join('\n\n') || 'Nenhum servidor ativo.', 3900))] });
  }

  return interaction.editReply('Comando não reconhecido.');
}
