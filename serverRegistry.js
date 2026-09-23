import { env } from '../config/env.js';

class ServerRegistry {
  #servers = new Map();

  update(payload) {
    const now = Date.now();
    const jobId = String(payload.jobId || '').trim();
    if (!jobId) return false;

    const players = Array.isArray(payload.players)
      ? payload.players.slice(0, 200).map((p) => ({
          userId: Number(p.userId) || 0,
          username: String(p.username || '').slice(0, 40),
          displayName: String(p.displayName || '').slice(0, 60),
          rank: String(p.rank || 'Nenhum').slice(0, 40),
        }))
      : [];

    this.#servers.set(jobId, {
      jobId,
      placeId: Number(payload.placeId) || 0,
      universeId: Number(payload.universeId) || 0,
      privateServerId: String(payload.privateServerId || '').slice(0, 100),
      players,
      playerCount: players.length,
      lastSeenAt: now,
      reportedAt: Number(payload.timestamp) || Math.floor(now / 1000),
    });
    return true;
  }

  cleanup() {
    const cutoff = Date.now() - env.activeServerTimeoutSeconds * 1000;
    for (const [jobId, server] of this.#servers) {
      if (server.lastSeenAt < cutoff) this.#servers.delete(jobId);
    }
  }

  getServers() {
    this.cleanup();
    return [...this.#servers.values()].sort((a, b) => b.playerCount - a.playerCount);
  }

  getOnlinePlayers() {
    const out = [];
    for (const server of this.getServers()) {
      for (const player of server.players) out.push({ ...player, jobId: server.jobId, placeId: server.placeId });
    }
    return out;
  }

  findPlayer(query) {
    const q = String(query ?? '').trim().toLowerCase();
    if (!q) return [];
    const numeric = /^\d+$/.test(q) ? Number(q) : null;
    return this.getOnlinePlayers().filter((p) =>
      (numeric && p.userId === numeric) ||
      p.username.toLowerCase().includes(q) ||
      p.displayName.toLowerCase().includes(q)
    );
  }

  stats() {
    const servers = this.getServers();
    return {
      servers: servers.length,
      players: servers.reduce((sum, s) => sum + s.playerCount, 0),
      lastSeenAt: servers.reduce((max, s) => Math.max(max, s.lastSeenAt), 0),
    };
  }
}

export const serverRegistry = new ServerRegistry();
