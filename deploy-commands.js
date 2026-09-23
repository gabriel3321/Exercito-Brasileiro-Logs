import 'dotenv/config';
import { REST, Routes } from 'discord.js';
import { commandDefinitions } from '../src/commands/definitions.js';

const token = process.env.DISCORD_TOKEN?.trim();
const clientId = process.env.DISCORD_CLIENT_ID?.trim();
const guildId = process.env.DISCORD_GUILD_ID?.trim();
if (!token || !clientId) throw new Error('Preencha DISCORD_TOKEN e DISCORD_CLIENT_ID no .env');

const rest = new REST({ version: '10' }).setToken(token);
const route = guildId ? Routes.applicationGuildCommands(clientId, guildId) : Routes.applicationCommands(clientId);
await rest.put(route, { body: commandDefinitions });
console.log(`[Discord] ${commandDefinitions.length} comandos publicados ${guildId ? 'no servidor de teste' : 'globalmente'}.`);
