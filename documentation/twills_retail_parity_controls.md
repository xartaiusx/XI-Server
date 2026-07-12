# Twills Retail-Parity Controls

Twills is a Mochirii QA administrator shaped like a long-time Final Fantasy XI
RDM/SCH character. Hidden GM level 5, the simulated creation date, and simulated
playtime are intentional QA exceptions. Content completion, rewards, currencies,
and gear are not considered legitimate solely because a local enum, database row,
or item definition exists.

## Sources Of Truth

1. Live Mochirii database and runtime behavior.
2. Local server scripts, data, save paths, and acceptance tests.
3. The generated implementation registry at
   `modules/custom/lua/twills_content_parity_registry.lua`.
4. Retail mechanics references such as the BG Wiki Merit Points, Abyssea Atma,
   Records of Eminence, Escha, Ambuscade, Dynamis, Odyssey, Sortie, and Limbus
   pages.

The tracked registry source is
`documentation/data/mochirii_content_parity.json`. Regenerate and validate it:

```bash
python3 tools/mochirii/content_parity_registry.py --repo-root .
python3 tools/mochirii/content_parity_registry.py --repo-root . --check
```

Runtime JSON/Markdown reports belong under the configured Mochirii runtime audit
directory, not in Git.

## Explicit Commands

`!twillsaudit` defaults to `core` and never mutates state:

- `!twillsaudit core`
- `!twillsaudit parity`
- `!twillsaudit content <registry-key>`
- `!twillsaudit merits`
- `!twillsaudit currency`
- `!twillsaudit gear`

`!twillsrepair` never mutates without an operation:

- `!twillsrepair core`
- `!twillsrepair metadata`
- `!twillsrepair merits`
- `!twillsrepair currency`
- `!twillsrepair unsupported --dry-run`
- `!twillsrepair gear --dry-run`

Unsupported-state and gear `--apply` modes are deliberately blocked until an
exact dry-run, database backup restoration proof, and complete GearSwap
replacement validation have been reviewed.

## Unsupported-State Evidence

Generate exact currency, inventory-slot, augment-blob, and key-item evidence:

```bash
python3 tools/mochirii/twills_unsupported_state.py \
  --repo-root . \
  --output-dir <runtime-root>/audits
```

The reporter is dry-run-only. It cannot mutate MariaDB. Titles, missions, and
quests remain unlisted until the registry has exact source-provenance mappings.

## Current Client Gate

Client updating was explicitly skipped for this implementation pass. Server
version enforcement remains unchanged. In-client repair, menu, GearSwap,
XIVHotbar, XivParty, and native Windower screenshot acceptance must wait until the
installed client version matches the server requirement; server-side controls,
reports, builds, and database-safe dry runs may proceed meanwhile.

## Retail References

- <https://www.bg-wiki.com/ffxi/Merit_Points>
- <https://www.bg-wiki.com/ffxi/Community_Red_Mage_Guide>
- <https://www.bg-wiki.com/ffxi/Category:Abyssea_Atma>
- <https://www.bg-wiki.com/ffxi/Category:Records_of_Eminence>
- <https://www.bg-wiki.com/ffxi/Category:Escha>
- <https://www.bg-wiki.com/ffxi/Category:Ambuscade>
- <https://www.bg-wiki.com/ffxi/Category:Dynamis_-_Divergence>
- <https://www.bg-wiki.com/ffxi/Category:Odyssey>
- <https://www.bg-wiki.com/ffxi/Category:Sortie>
- <https://www.bg-wiki.com/ffxi/Category:Limbus>
