# EB Logs — Discord + Roblox + Anticheat

Projeto preparado para o sistema descrito no prompt: bot de Discord focado em logs, backend HTTP seguro, jogadores/servidores ativos, histórico recente e anticheat server-side de Fly integrado ao painel administrativo.

## Arquitetura

```text
Roblox Server
  ├─ Painel administrativo
  ├─ EBFlyAuthorization
  ├─ EBAntiCheat
  └─ EBLogBridge (fila/batch + heartbeat)
          │ HTTPS
          ▼
Node.js / Railway
  ├─ API Express
  ├─ autenticação token + timestamp + nonce
  ├─ registro dos servidores ativos
  ├─ histórico JSONL de 7 dias
  └─ discord.js
          │
          ▼
Discord
  ├─ #logs-gerais
  ├─ #logs-admin
  ├─ #logs-punicoes
  ├─ #logs-anticheat
  └─ #logs-cargos
```

## 1. Criar o bot no Discord

1. Entre no **Discord Developer Portal**.
2. Crie uma nova Application.
3. Vá em **Bot** e crie/ative o bot.
4. Copie o token do bot. Não envie esse token para ninguém e não coloque no GitHub.
5. Copie o **Application ID** na página General Information.
6. Este projeto só precisa do intent `Guilds`; não precisa de Message Content para os slash commands.
7. No OAuth2/URL Generator, convide o bot com os escopos `bot` e `applications.commands`.
8. Dê ao bot permissão para ver os canais e enviar mensagens/embeds nos canais de logs.

## 2. Criar os canais

Exemplo:

- `#logs-gerais`
- `#logs-admin`
- `#logs-punicoes`
- `#logs-anticheat`
- `#logs-cargos`

Ative o modo desenvolvedor do Discord, copie o ID de cada canal e guarde para o `.env`/Railway.

## 3. Rodar localmente

Instale Node.js 20 ou mais novo e, dentro desta pasta:

```bash
npm install
```

Copie `.env.example` para `.env` e preencha.

Gere o segredo Roblox/backend:

```bash
npm run secret
```

Copie o resultado para:

```env
ROBLOX_SHARED_SECRET=resultado_aqui
```

E coloque **o mesmo valor** no instalador Roblox em `LOG_SHARED_SECRET`.

Publique os slash commands:

```bash
npm run deploy:commands
```

Inicie:

```bash
npm start
```

Teste no navegador:

```text
http://localhost:3000/health
```

## 4. Slash Commands

- `/log ativos` — jogadores atualmente vistos pelos heartbeats Roblox
- `/log status` — bot, servidores, jogadores e quantidade de logs
- `/log ultimos` — últimos logs recebidos
- `/player info` — busca online por Username, DisplayName ou UserId
- `/server ativos` — lista servidores ativos
- `/help` — ajuda

Se `DISCORD_GUILD_ID` estiver configurado, os comandos são publicados só naquele servidor para testes e normalmente aparecem mais rápido. Depois você pode apagar essa variável e executar novamente o deploy para publicar globalmente.

## 5. GitHub

Antes de enviar o projeto:

```bash
git init
git add .
git commit -m "EB Logs v1"
```

O `.gitignore` já bloqueia `.env`, `node_modules` e os arquivos de dados locais. **Confira novamente antes de dar push.**

Crie um repositório vazio no GitHub e siga os comandos apresentados pelo GitHub para adicionar o remote e fazer push.

## 6. Railway

1. Crie um projeto no Railway.
2. Escolha deploy a partir do repositório GitHub.
3. Em Variables, crie todas as variáveis necessárias do `.env.example`.
4. Gere um domínio público HTTPS para o serviço.
5. Copie a URL, por exemplo:

```text
https://seu-projeto.up.railway.app
```

6. No instalador Roblox, configure:

```lua
local LOG_BACKEND_URL = "https://seu-projeto.up.railway.app"
local LOG_SHARED_SECRET = "O_MESMO_ROBLOX_SHARED_SECRET_DO_RAILWAY"
```

### Volume recomendado

Para manter `logs.jsonl` entre reinícios/deploys, adicione um Volume no Railway montado em:

```text
/data
```

E configure:

```env
DATA_DIR=/data
```

Sem volume, os logs do bot podem desaparecer em um novo deploy. O histórico do painel Roblox continua sendo separado no DataStore do jogo.

## 7. Roblox Studio

Use `roblox/EB_Sistema_Completo_V7_LOGS_DISCORD_ANTICHEAT.lua`.

Antes de colar na Command Bar, troque `LOG_BACKEND_URL` e `LOG_SHARED_SECRET`.

Depois execute com o Play parado. O sistema cria os módulos server-only e integra o anticheat ao painel.

Também é necessário permitir requisições HTTP nas configurações de segurança do jogo para que `HttpService:RequestAsync()` funcione.

## 8. Segurança da API

Cada requisição Roblox contém:

- `X-EB-Token`: segredo compartilhado server-only
- `X-EB-Timestamp`: horário da requisição
- `X-EB-Nonce`: GUID único

O backend:

- compara o token com comparação de tempo constante;
- rejeita timestamp antigo;
- rejeita nonce já usado;
- limita requisições por minuto;
- aceita payload limitado em tamanho.

O segredo não fica em `LocalScript` nem `ReplicatedStorage`.

## 9. Anticheat Fly

A autorização legítima é guardada no módulo **server-only** `EBFlyAuthorization`.

O detector não bane simplesmente porque alguém ficou dois segundos no ar. Ele combina, em várias amostras:

- distância do chão por Raycast;
- `FloorMaterial`;
- tempo de hover;
- velocidade vertical;
- velocidade horizontal;
- estado do Humanoid;
- deslocamento entre amostras;
- múltiplos ticks confirmados;
- score acumulado com decaimento.

São ignoradas/consideradas situações como:

- spawn recente;
- Fly autorizado pelo painel;
- grace period administrativo de Bring/Respawn;
- jogador sentado em veículo;
- escalada;
- natação;
- personagem ancorado.

Ao confirmar Fly sem autorização, o padrão é:

1. criar evidências;
2. enviar log `ANTICHEAT_BAN`;
3. salvar ban no mesmo DataStore do painel;
4. registrar no histórico global do painel;
5. expulsar o jogador.

### Importante

Nenhum anticheat de movimento pode garantir zero falso positivo em todos os mapas. Teste com seus veículos, trampolins, canhões, teletransportes e sistemas de física. Se algum sistema legítimo mover jogadores de maneira extrema, dê grace period server-side usando `EBFlyAuthorization.GrantGrace()`.

## 10. Teste recomendado antes de publicar

1. Teste o bot e `/health`.
2. Teste `/log status` no Discord.
3. Entre no jogo e confirme `JOIN` em `#logs-gerais`.
4. Use Warn/Kick em servidor de teste e confira os embeds.
5. Use Fly pelo painel e confirme que o anticheat não pune.
6. Use Unfly e confirme que a autorização é removida.
7. Teste FlyAll/UnflyAll.
8. Simule movimento suspeito apenas em ambiente de desenvolvimento antes de confiar no AutoBan.
9. Se quiser testar sem ban automático, mude temporariamente `AutoBan = false` em `EBServerConfig`.

## Dono/Sub-Dono do painel incluído

- Dono: `468762368`
- Sub-Dono: `2887861665`

Esses valores vêm da versão atual do painel usada como base para o instalador V7.
