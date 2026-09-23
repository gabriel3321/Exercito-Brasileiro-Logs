import fs from 'node:fs/promises';
import path from 'node:path';
import { env } from '../config/env.js';

class LogStore {
  #items = [];
  #file;
  #writeChain = Promise.resolve();

  async init() {
    await fs.mkdir(env.dataDir, { recursive: true });
    this.#file = path.join(env.dataDir, 'logs.jsonl');

    try {
      const raw = await fs.readFile(this.#file, 'utf8');
      const cutoff = this.#cutoff();
      this.#items = raw
        .split(/\r?\n/)
        .filter(Boolean)
        .map((line) => {
          try { return JSON.parse(line); } catch { return null; }
        })
        .filter((x) => x && Number(x.timestamp) >= cutoff)
        .slice(-env.maxRecentLogsInMemory);
      await this.prune();
    } catch (error) {
      if (error.code !== 'ENOENT') console.error('[LogStore] Falha ao carregar:', error);
    }
  }

  #cutoff() {
    return Math.floor(Date.now() / 1000) - env.logRetentionDays * 86400;
  }

  async add(item) {
    const clean = { ...item, timestamp: Number(item.timestamp) || Math.floor(Date.now() / 1000) };
    this.#items.push(clean);
    if (this.#items.length > env.maxRecentLogsInMemory) this.#items.shift();

    const line = `${JSON.stringify(clean)}\n`;
    this.#writeChain = this.#writeChain.then(() => fs.appendFile(this.#file, line, 'utf8'));
    await this.#writeChain;
    return clean;
  }

  getRecent(limit = 10) {
    const cutoff = this.#cutoff();
    this.#items = this.#items.filter((x) => Number(x.timestamp) >= cutoff);
    return this.#items.slice(-Math.max(1, Math.min(50, limit))).reverse();
  }

  size() {
    return this.#items.length;
  }

  async prune() {
    const cutoff = this.#cutoff();
    this.#items = this.#items.filter((x) => Number(x.timestamp) >= cutoff).slice(-env.maxRecentLogsInMemory);
    const temp = `${this.#file}.tmp`;
    const body = this.#items.map((x) => JSON.stringify(x)).join('\n') + (this.#items.length ? '\n' : '');
    await fs.writeFile(temp, body, 'utf8');
    await fs.rename(temp, this.#file);
  }
}

export const logStore = new LogStore();
