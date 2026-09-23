import crypto from 'node:crypto';
import { env } from '../../config/env.js';

const usedNonces = new Map();

function safeEqual(a, b) {
  const aa = Buffer.from(String(a || ''));
  const bb = Buffer.from(String(b || ''));
  if (aa.length !== bb.length) return false;
  return crypto.timingSafeEqual(aa, bb);
}

function pruneNonces(now) {
  for (const [nonce, expires] of usedNonces) if (expires <= now) usedNonces.delete(nonce);
}

export function robloxAuth(req, res, next) {
  const token = req.get('x-eb-token');
  const timestamp = Number(req.get('x-eb-timestamp'));
  const nonce = String(req.get('x-eb-nonce') || '');
  const now = Math.floor(Date.now() / 1000);

  if (!safeEqual(token, env.robloxSharedSecret)) return res.status(401).json({ ok: false, error: 'unauthorized' });
  if (!Number.isFinite(timestamp) || Math.abs(now - timestamp) > env.authMaxSkewSeconds) {
    return res.status(401).json({ ok: false, error: 'expired_request' });
  }
  if (!/^[A-Za-z0-9-]{10,100}$/.test(nonce)) return res.status(400).json({ ok: false, error: 'invalid_nonce' });

  pruneNonces(now);
  if (usedNonces.has(nonce)) return res.status(409).json({ ok: false, error: 'replayed_request' });
  usedNonces.set(nonce, now + env.authMaxSkewSeconds * 2);
  next();
}
