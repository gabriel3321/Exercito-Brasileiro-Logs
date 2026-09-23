import express from 'express';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import { env } from '../config/env.js';
import { robloxAuth } from './middleware/robloxAuth.js';
import { serverRegistry } from '../services/serverRegistry.js';
import { logStore } from '../services/logStore.js';
import { discordLogService } from '../services/discordLogService.js';

function normalizeLog(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const timestamp = Number(raw.timestamp) || Math.floor(Date.now() / 1000);
  return {
    id: String(raw.id || `log-${timestamp}-${Math.random().toString(36).slice(2, 10)}`).slice(0, 120),
    timestamp,
    category: ['general', 'admin', 'punishment', 'anticheat', 'rank'].includes(raw.category) ? raw.category : 'admin',
    action: String(raw.action || 'LOG').slice(0, 80),
    reason: raw.reason == null ? null : String(raw.reason).slice(0, 500),
    detail: raw.detail == null ? null : String(raw.detail).slice(0, 1000),
    admin: raw.admin && typeof raw.admin === 'object' ? raw.admin : null,
    target: raw.target && typeof raw.target === 'object' ? raw.target : null,
    extra: raw.extra && typeof raw.extra === 'object' ? raw.extra : null,
    server: raw.server && typeof raw.server === 'object' ? raw.server : null,
  };
}

export function createApiServer() {
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(express.json({ limit: '128kb' }));
  app.use(rateLimit({ windowMs: 60_000, limit: 240, standardHeaders: true, legacyHeaders: false }));

  app.get('/health', (_req, res) => {
    const stats = serverRegistry.stats();
    res.json({ ok: true, uptimeSeconds: Math.floor(process.uptime()), ...stats, storedLogs: logStore.size() });
  });

  app.post('/api/roblox/heartbeat', robloxAuth, (req, res) => {
    if (!serverRegistry.update(req.body)) return res.status(400).json({ ok: false, error: 'invalid_heartbeat' });
    res.json({ ok: true });
  });

  app.post('/api/roblox/logs/batch', robloxAuth, async (req, res) => {
    const entries = Array.isArray(req.body?.logs) ? req.body.logs.slice(0, 25) : [];
    if (!entries.length) return res.status(400).json({ ok: false, error: 'empty_batch' });

    let accepted = 0;
    for (const raw of entries) {
      const log = normalizeLog(raw);
      if (!log) continue;
      await logStore.add(log);
      discordLogService.enqueue(log);
      accepted += 1;
    }
    res.json({ ok: true, accepted });
  });

  app.use((error, _req, res, _next) => {
    console.error('[API]', error);
    res.status(500).json({ ok: false, error: 'internal_error' });
  });

  return app.listen(env.port, '0.0.0.0', () => {
    console.log(`[API] Online na porta ${env.port}`);
  });
}
