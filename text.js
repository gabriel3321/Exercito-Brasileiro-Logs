export function cleanText(value, max = 1024) {
  const text = String(value ?? '').replace(/\u0000/g, '').trim();
  if (!text) return '-';
  return text.length > max ? `${text.slice(0, Math.max(0, max - 1))}…` : text;
}

export function discordTimestamp(unixSeconds) {
  const n = Number(unixSeconds);
  if (!Number.isFinite(n) || n <= 0) return '-';
  return `<t:${Math.floor(n)}:F>`;
}

export function humanUptime(seconds) {
  seconds = Math.max(0, Math.floor(seconds));
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return [d && `${d}d`, h && `${h}h`, m && `${m}m`, `${s}s`].filter(Boolean).join(' ');
}
