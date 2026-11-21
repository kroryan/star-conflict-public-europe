# Persistent playerbots in open space

## Current finding

The current solo profile fills supported matchmaking queues with battle AI. It does not create authenticated player sessions. The `withBots` setting in the sector and league queues belongs to matchmaking for universe battles; it is not a switch for filling free-space zones with logged-in pilots.

The game data does contain `designers:AddBot()`. In free-space mode it calls `SV_SpawnNpc()`, enables ship AI and gives the entity a self-defence order. That creates an NPC ship, not an account-backed player: it does not establish an Authenticator session, own a hangar, or participate in Shard, ChatServer, ClanServer, or QuestServer as a player.

The released server is a set of executable services. The repository contains configuration, game-data overrides, and deployment scripts, but no source for Hub, Authenticator, Shard, Universe, ZoneCoordinator, ZoneInstance, or the social services. The official server guide describes those services and their separate responsibilities: <https://star-conflict.com/>.

**Conclusion:** a full playerbot population cannot be implemented with the current configuration knobs or by inserting account documents into MongoDB. A database row does not perform the login handshake, maintain a live connection, enter a zone, or send gameplay actions. The actual client protocol or a supported server-side bot-session API would be required. Neither is currently exposed by this kit.

## Safe implementation plan

### Gate 0: prove one real session

1. Keep the server local-only and back up MongoDB.
2. Identify a supported interface, if one exists, for an automated client to authenticate and enter free space. Do not write fabricated online/session state directly to MongoDB.
3. Connect one test bot and verify all of the following from the server and client: it authenticates, appears as a pilot in the zone, remains online, can receive movement/combat actions, and disconnects cleanly.
4. Stop here if no supported session interface can be found. The present repository cannot add hooks inside the closed server executables.

### Gate 1: one-bot controller

If Gate 0 succeeds, add a separate `BotDirector` process with a fail-closed configuration. It should:

- activate only after the configured human account enters free space;
- manage one bot at first, using a dedicated test account and a stable pilot profile;
- track `offline`, `logging_in`, `entering_zone`, `active`, `leaving`, and `cooldown` states;
- stop and clean up sessions on shutdown, server maintenance, or human disconnect;
- log each transition and enforce a hard maximum independent of database contents.

### Gate 2: gradual population

After the one-bot test is stable, make the scheduler configurable for one-at-a-time or batches of ten. Use an explicit maximum, initial delay, interval, and cooldown. Start at a conservative rate and measure each step before increasing it. Never default to 300 active bots.

### Gate 3: behavior and native AI

Separate high-level activities (patrol, travel, assist, return to station, queue for a supported battle) from ship control. Reuse the existing combat AI only if an exposed API can attach it to the authenticated bot session. `designers:AddBot()` is useful for NPC combat and ambient traffic, but does not satisfy the player-session requirement.

### Gate 4: social systems

Add persistent profiles, squads, chat, corporations, roles, and mission/progression behavior only through the same supported player-facing service calls used by real pilots. Validate one account and one corporation before generating more. Keep trade and reward actions disabled until their side effects are understood.

### Gate 5: load and acceptance

Increase in measured steps (1, 5, 10, 25, 50, then higher) while recording CPU, memory, network traffic, service latency, MongoDB load, reconnects, and zone stability. Consider 300 supported only after a long-running soak test.

Acceptance for a full playerbot feature requires real online sessions visible in the zone, clean reconnect/disconnect, autonomous movement and combat, persistent profiles, and working social features. A ship spawned by `SV_SpawnNpc()` or an account document in MongoDB does not count as a passing result.

## Status

This document records the feasibility gate and design. No playerbot sessions are created by the current server profile. The existing battle-bot matchmaking remains unchanged. Do not advertise open-world playerbots until Gate 0 has passed.
