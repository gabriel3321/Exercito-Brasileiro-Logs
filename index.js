import { createDiscordClient } from './bot/client.js';
import { createApiServer } from './api/server.js';
import { logStore } from './services/logStore.js';

await logStore.init();
createDiscordClient();
createApiServer();

setInterval(() => {
  logStore.prune().catch((e) => console.error('[LogStore] prune:', e));
}, 6 * 60 * 60 * 1000).unref();
