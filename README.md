# Old Gods Guild Audit (OGA)

[![Source validation](https://github.com/marcusawereally/oldgodsguildaudit/actions/workflows/source-validation.yml/badge.svg)](https://github.com/marcusawereally/oldgodsguildaudit/actions/workflows/source-validation.yml)
[![Discord](https://img.shields.io/badge/Discord-Old%20Gods-5865F2)](https://discord.gg/oldgods)

Guild audits, roster review, recruiting and officer tools for World of Warcraft.

## Downloads and installation

Get installable versioned ZIPs from [GitHub Releases](https://github.com/marcusawereally/oldgodsguildaudit/releases). Choose Retail or Forever, extract `OldGodsGuildAudit` into the matching game's `Interface/AddOns` directory, and restart WoW.

For source installs, use `OldGodsGuildAudit/` for Retail or `forever/OldGodsGuildAudit/` for Forever. Keep the game variants separate. Forever compatibility depends on its current client APIs and needs in-game verification.

The initial public source snapshot is not a new production release. Tagged downloads are published after the normal release checks pass.

## Features

- Scored guild checklist covering membership targets, inactivity, public notes, MOTD, recruitment, supported guild-bank data, calendar requirements and manual Discord checks.
- Up to 50 timestamped audit reports saved in WoW SavedVariables.
- Searchable roster, Main/Alt context, inactivity review and recorded roster events.
- Controlled guild-removal and rank-action preparation; guild permissions and player interaction still apply.
- Current-zone and level-range recruiting searches, quiet-zone filters, recruiting history and one-player-at-a-time guild invitations.
- Local Ban List with reviewed Guild Roster Manager imports.
- Chapter settings and rank/bank policies, manual review and result overrides.
- Synchronized character and raffle tools through the optional Old Gods Companion and website.
- Individually confirmed past-calendar cleanup and one-pet-per-click Spazzy bank utility.
- Dark, Light, Hot Pink and Hot Dog Stand themes, feedback and troubleshooting tools.

## Commands and access

Open the addon with `/oga` or the minimap button. Audit and chapter administration require the appropriate guild rank. Raffle tools are also available through `/ograffle`.

## Companion integration

Old Gods Companion can process saved addon data and synchronize authorized guild, character and raffle information with the website. WoW writes SavedVariables on `/reload` or logout; synchronization is not live access to WoW memory. Uploads and account/chapter permissions are configured separately. The Companion is optional for in-game auditing and recruiting.

## Game limits

Discord checks are manual. Bank checks require the bank to be open and data loaded. Recruiting follows Blizzard's query limits. Protected actions require player interaction and permissions. Unsupported or unknown data remains reviewable rather than being assumed valid.

## Feedback and development

[Report a bug or request a feature](https://github.com/marcusawereally/oldgodsguildaudit/issues). Include your addon version and whether you use Retail or Forever. See [Contributing](CONTRIBUTING.md).

This public repository contains addon source only. Verified snapshots and release ZIPs are published from the combined development workspace. It contains no Companion/server code or private guild SavedVariables.

[Old Gods website](https://oldgods.io) · [Dungeon Madness](https://github.com/marcusawereally/oldgodsdungeonmadness)
