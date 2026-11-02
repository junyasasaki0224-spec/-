# CLAUDE.md — あやかし釣り (Yokai Fishing)

Roblox game written in Luau, synced to Studio with Rojo. Japanese comments/docs; keep that style.

## Commands
- Build: `rojo build default.project.json -o YokaiFishing.rbxl`
- Format: `stylua src tests` (CI runs `stylua --check src tests`)
- Tests: `lune run tests/run.luau` (pure modules only: Config, Lib/Roll, Lib/Pricing, Lib/WorldClock, Lib/Format, Locale)
- Economy pacing: `lune run tests/economy_sim.luau`

## Architecture
- `src/shared/Config/*` is the single source of game data. New fish/spots/quests = add rows, no code. `Config.Validate()` runs at server start and in tests.
- `src/shared/Lib/Roll.luau` and `Pricing.luau` are pure (rng is injected) so they can be unit-tested; keep them free of Roblox services.
- Server services live in `src/server/Services`, are wired in `src/server/init.server.luau` through a registry `S` (`S.Data`, `S.Fishing`, …) with `init(S)` then `start()`. Do not `require` services from each other directly (avoids cycles); use `S`.
- All client→server traffic goes through `RemoteGuard.connect` (rate limit + pcall). Shop/settings actions share the `Request` remote and are routed by `handleRequest`.
- Client modules in `src/client/Controllers` only render and send intents. UI is built in code via `src/client/UI/Kit.luau`.
- World is generated at runtime (`src/server/World`): Terrain + Parts. Text on signs/prompts is localized on the client via the `LocKey` attribute.

## Rules (security / privacy)
- Server decides every outcome (fish, weight, mutation, price, rewards). Never accept these from the client.
- Validate every remote argument with `RemoteGuard.isNumber/isInt/isId`; reject NaN/inf/long strings.
- Store only game progress keyed by UserId. No names, chat, device info. Pass `{ userId }` to UpdateAsync for GDPR erasure; keep `DataService.eraseUser` working.
- `ProcessReceipt`: grant → record PurchaseId → save → only then `PurchaseGranted`.
- No user-typed text is shown to others; if that is ever added it must go through TextService filtering.
- Never commit secrets (.env, API keys). Product IDs are public and live in `Config/Products.luau`.
