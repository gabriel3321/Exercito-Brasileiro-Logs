import { SlashCommandBuilder } from 'discord.js';

export const commandDefinitions = [
  new SlashCommandBuilder()
    .setName('log')
    .setDescription('Logs e status da integração Roblox')
    .addSubcommand((s) => s.setName('ativos').setDescription('Mostra jogadores online agora'))
    .addSubcommand((s) => s.setName('status').setDescription('Mostra o status Roblox ↔ Bot'))
    .addSubcommand((s) => s.setName('ultimos').setDescription('Mostra logs recentes').addIntegerOption((o) => o.setName('quantidade').setDescription('1 a 15').setMinValue(1).setMaxValue(15))),

  new SlashCommandBuilder()
    .setName('player')
    .setDescription('Consulta jogadores online')
    .addSubcommand((s) => s.setName('info').setDescription('Pesquisa username, DisplayName ou UserId').addStringOption((o) => o.setName('busca').setDescription('Nome ou UserId').setRequired(true))),

  new SlashCommandBuilder()
    .setName('server')
    .setDescription('Servidores Roblox')
    .addSubcommand((s) => s.setName('ativos').setDescription('Lista servidores ativos')),

  new SlashCommandBuilder().setName('help').setDescription('Mostra os comandos disponíveis'),
].map((x) => x.toJSON());
