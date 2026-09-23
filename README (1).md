# Roblox — instalação

A opção mais simples é usar **EB_Sistema_Completo_V7_LOGS_DISCORD_ANTICHEAT.lua**.

Ele parte do painel administrativo V6 e adiciona:

- `ServerScriptService/EBServerConfig` (segredos server-only)
- `ServerScriptService/EBLogBridge` (fila de logs + heartbeat)
- `ServerScriptService/EBFlyAuthorization` (fonte de verdade do Fly)
- `ServerScriptService/EBAntiCheat` (detecção server-side)
- integração do `Fly`, `Unfly`, `FlyAll` e `UnflyAll` com o anticheat
- log de entrada/saída, punições, cargos, comandos e anticheat

## Antes de executar

Abra o instalador e, no começo, altere:

```lua
local LOG_BACKEND_URL = "https://SEU-PROJETO.up.railway.app"
local LOG_SHARED_SECRET = "MESMO_SEGREDO_DA_VARIAVEL_ROBLOX_SHARED_SECRET"
```

O segredo fica dentro de `ServerScriptService`, nunca em `ReplicatedStorage` ou `LocalScript`.

Depois:

1. Pare o Play.
2. Abra `Exibir > Command Bar`.
3. Cole o arquivo inteiro.
4. Execute uma vez.
5. Publique/salve.
6. Ative requisições HTTP do jogo nas configurações de segurança do Roblox Studio.
7. Dê Play e veja a janela Output.

## Fly legítimo

O anticheat usa uma tabela server-side em `EBFlyAuthorization`. O atributo `AdminFlyAuthorized` existe apenas para depuração/visual e **não é usado como prova de permissão**.

Quando o painel executa Fly, o servidor chama `FlyAuth.Grant`. Quando executa Unfly, chama `FlyAuth.Revoke`. O FlyAll usa a mesma função para cada jogador, portanto todos ficam autorizados corretamente.

`Bring` e `Respawn` recebem alguns segundos de grace period para evitar falso positivo por teleporte administrativo.
