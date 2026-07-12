# Abyssea Atma Parity

Mochirii models all 145 locally defined Atma through the normal Atma status
effect. Static bonuses use existing `xi.mod` values, while day, HP threshold,
and equipped-weapon conditions are refreshed by the Atma effect tick. Atma
bonuses remain active only in Abyssea zones and are removed with the status
effect.

## Source And Scaling

- The local modifier engine is the implementation authority.
- Retail effect names and values are cross-checked against the
  [BG Wiki Abyssea Atma table](https://www.bg-wiki.com/ffxi/Atma).
- Elemental weapon-skill fTP uses Mochirii's `/256` elemental fTP modifiers.
- Damage-taken and haste modifiers use Mochirii's existing `/10000` units.
- Minor, major, and superior unnamed tiers follow the magnitudes already used
  by neighboring Atma definitions in this file.

Royal Lineage's cruor bonus is applied by `xi.abyssea.addCruor`, which keeps
the normal currency write and result-message flow. Dragon Rider's Wyvern HP is
attached to the active Wyvern and removed when the Atma is purged.

## Explicit Deferrals

Three sub-effects remain documented rather than approximated:

- Ducal Guard's guard-specific damage reduction has no dedicated local
  modifier.
- Master Crafter's generic status-effect enhancement has no local universal
  effect-potency modifier.
- Savior's generic status-effect enhancement has the same engine limitation.

The other effects on those Atma are active. The content parity report keeps
Abyssea `partial` until these sub-effects and the acquisition paths have live
acceptance coverage.

## Verification

Run the focused Lua system tests and the implementation-aware source audit:

```bash
./build/src/test/xi_test --keep-going --filter "Abyssea Atma"
python3 tools/mochirii/content_parity_registry.py --repo-root . --check
```

Acceptance requires 145 definitions, zero effectless Atma, nine conditional
Atma definitions, and exactly three explicitly deferred sub-effects.
