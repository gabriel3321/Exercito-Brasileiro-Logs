import { Client, GatewayIntentBits } from 'discord.js';
import { env } from '../config/env.js';
import { handleInteraction } from '../commands/handlers.js';
import { discordLogService } from '../services/discordLogService.js';

export function createDiscordClient() {
  const client = new Client({ intents: [GatewayIntentBits.Guilds] });

  client.once('ready', () => {
    console.log(`[Discord] Online como ${client.user.tag}`);
    discordLogService.attachClient(client);
  });

  client.on('interactionCreate', (interaction) => {
    handleInteraction(interaction).catch(async (error) => {
      console.error('[Discord] Erro em comando:', error);
      const payload = { content: 'Ocorreu um erro ao executar o comando.' };
      if (interaction.deferred || interaction.replied) await interaction.editReply(payload).catch(() => {});
      else await interaction.reply(payload).catch(() => {});
    });
  });

  client.login(env.discordToken);
  return client;
}
