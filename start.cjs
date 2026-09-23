const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const root = process.cwd();
const ignored = new Set(['node_modules', '.git', '.railway', '.cache']);

function walk(dir, depth = 0) {
  if (depth > 6) return [];
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }

  const found = [];
  for (const entry of entries) {
    if (ignored.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      found.push(...walk(full, depth + 1));
    } else if (entry.isFile() && entry.name === 'index.js' && path.basename(path.dirname(full)) === 'src') {
      found.push(full);
    }
  }
  return found;
}

function printTree(dir, prefix = '', depth = 0) {
  if (depth > 3) return;
  let entries = [];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true })
      .filter(e => !ignored.has(e.name))
      .slice(0, 80);
  } catch {
    return;
  }

  for (const entry of entries) {
    console.log(prefix + (entry.isDirectory() ? '📁 ' : '📄 ') + entry.name);
    if (entry.isDirectory()) {
      printTree(path.join(dir, entry.name), prefix + '  ', depth + 1);
    }
  }
}

const direct = path.join(root, 'src', 'index.js');
let target = fs.existsSync(direct) ? direct : null;

if (!target) {
  const candidates = walk(root)
    .sort((a, b) => a.split(path.sep).length - b.split(path.sep).length);
  target = candidates[0] || null;
}

if (!target) {
  console.error('\n[EB Railway] ERRO: não encontrei nenhum arquivo src/index.js no deploy.');
  console.error('[EB Railway] Estrutura recebida pelo Railway:\n');
  printTree(root);
  console.error('\n[EB Railway] Envie a pasta src para o GitHub ou ajuste Settings > Root Directory no Railway.');
  process.exit(1);
}

console.log('[EB Railway] Iniciando bot em:', path.relative(root, target));
const child = spawn(process.execPath, [target], {
  cwd: path.dirname(path.dirname(target)),
  stdio: 'inherit',
  env: process.env,
});

child.on('exit', (code, signal) => {
  if (signal) {
    console.error('[EB Railway] Processo encerrado por sinal:', signal);
    process.exit(1);
  }
  process.exit(code ?? 0);
});
