Tools
========================

## Database Tool
`python dbtool.py`  
`python dbtool.py backup` - creates a whole database backup in `../sql/backups/`  
`python dbtool.py backup lite` - creates a backup only of tables defined in settings  
`python dbtool.py update` - performs an express update with backup and migrations if necessary  
`python dbtool.py update full` - performs a full update with backup and migrations  
`python dbtool.py migrate` - checks and performs any needed migrations

This tool creates or connects to the database defined in
`../settings/network.lua`. It allows the user to backup or restore the database,
import any `custom.sql` stored in `../sql/backups/`, and import the SQL files
tracked by the Mochirii checkout. This tool also handles data migrations for
character data.

## Price Checker
`python price_checker.py`

This tool checks NPC and guild shop prices to see if anything is being sold for less than the buyback price.

## Festive Moogle Tool
`python give_items.py`

This tool is used to distribute the following items:  
- Nomad Cap  
- Moogle Cap  
- Moogle Rod  
- Harpsichord  
- Stuffed Chocobo  
- Tidal Talisman  
- Destrier Beret  
- Chocobo Shirt  

## Announce
`python announce.py "<your message>"`

Sends `<your message>` to every character, in every zone, on every map process.  

Setup
========================

## Current Windows Tooling

The current Mochirii workstation has the following project tools installed and
verified as of 2026-06-25:

- Git
- GitHub CLI `gh` 2.95.0, installed but not locally authenticated
- Python 3.12
- CMake
- Ninja
- LLVM clang-format 22.1.8
- LuaJIT 2.1 for Lua 5.1-style syntax checks used by the server
- Lua 5.4 for general Lua CLI work
- Lua Language Server 3.18.2
- StyLua 2.5.2 for optional Lua formatting checks
- Node.js and npm for Windower/client helper tooling where needed

Use LuaJIT for syntax validation of server Lua modules because the map server
embeds LuaJIT-compatible semantics. StyLua is available, but do not apply a
large mechanical Lua formatting pass unless the task explicitly asks for it.

Recommended local checks for Mochirii custom Lua:

```powershell
luajit -bl modules/custom/lua/trust_retail_parity.lua NUL
luajit -bl modules/custom/lua/trust_action_logger.lua NUL
luajit -bl modules/custom/commands/trustparty.lua NUL
```

After C++ changes, rebuild the relevant server target:

```powershell
cmake --build build --target xi_map --config Release --parallel 6
```

## Installing Python
`python3 --version` or `py -3 --version`

**This requires Python 3 and pip.**  
**Website:** https://www.python.org/downloads/  
Download the latest version from the website or check your package manager.

## Installing Dependencies
`pip install -r requirements.txt`

**MariaDB** - MariaDB is required to interact with the database.  
**GitPython** - GitPython is required to compare database versions.  
**PyYAML** - PyYAML is required to read/write settings.  
**Colorama** - Colorama is required to make colored terminal text.  
**zmq** - ZeroMQ is required for sending messages to the server.  
**Pylint** - Pylint is a static code analyser.  
**Black** - Black is a Python code formatter.  

## Other
`./install-systemd-service.sh` - Installs a systemd service for running the servers on Linux.  
`./run_clang_format.py` - Formats C++ code. Run from repo root.  
