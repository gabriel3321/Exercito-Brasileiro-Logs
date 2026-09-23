import { env } from '../config/env.js';
import { buildLogEmbed } from '../utils/embeds.js';

const CATEGORY_CHANNEL = {
  general: 'general',
  admin: 'admin',
  punishment: 'punishments',
  anticheat: 'anticheat',
  rank: 'ranks',
};

class DiscordLogService {
  #client = null;
  #queue = [];
  #running = false;

  attachClient(client) {
    this.#client = client;
    if (!this.#running) {
      this.#running = true;
      this.#worker().catch((e) => console.error('[DiscordQueue]', e));
    }
  }

  enqueue(log) {
    this.#queue.push(log);
    if (this.#queue.length > 1000) this.#queue.shift();
  }

  async #worker() {
    while (true) {
      const item = this.#queue.shift();
      if (!item) {
        await new Promise((r) => setTimeout(r, 250));
        continue;
      }
      try {
        await this.#send(item);
      } catch (error) {
        console.error('[DiscordLog] Falha ao enviar:', error?.message || error);
      }
      await new Promise((r) => setTimeout(r, 650));
    }
  }

  async #send(log) {
    if (!this.#client?.isReady()) return;
    const key = CATEGORY_CHANNEL[log.category] || 'admin';
    const channelId = env.channels[key] || env.channels.admin || env.channels.general;
    if (!channelId) return;
    const channel = await this.#client.channels.fetch(channelId).catch(() => null);
    if (!channel?.isTextBased()) return;
    await channel.send({ embeds: [buildLogEmbed(log)] });
  }
}

export const discordLogService = new DiscordLogService();
