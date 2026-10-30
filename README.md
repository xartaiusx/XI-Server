# Mochirii

Mochirii is a local Final Fantasy XI server project built on [LandSandBoat](https://github.com/LandSandBoat/server), focused on gameplay development, client integration, and quality assurance.

The server uses **C++23, Lua/LuaJIT, and MariaDB**, with CMake builds and Python, PowerShell, and shell tools.

## Project focus

- Improve Trust combat behavior while preserving individual roles.
- Refine Windower integration, equipment workflows, hotbars, party layouts, and graphics.
- Support character, progression, and crafting QA through custom modules.
- Maintain server controls, restore manifests, and reusable configuration templates.

Retail parity remains an ongoing development goal. Changes require relevant tests and in-game verification where applicable.

## Getting started

Use the [setup guide](docs/wiki/Quick-Start-Guide.md) and [client setup guide](docs/wiki/Client-Setup-Windows.md). Follow upstream installation instructions using this repository and its submodules for the source checkout.

Check the [client compatibility settings](settings/default/login.lua) before connecting. Obtain the Final Fantasy XI client and third-party assets separately.

## Documentation

- [Trust development](documentation/trust_retail_parity.md)
- [Client integration and QA](documentation/client_mod_admin_plan.md)
- [Graphics configuration](documentation/client_graphics_stack.md)
- [Restore tools and procedures](documentation/portable_restore.md)
- [Modules](docs/wiki/Module-Guide.md) and [testing](docs/wiki/Testing.md)
- [Contributing](CONTRIBUTING.md) and [security](SECURITY.md)

## Repository policy

Keep credentials, private account data, database backups, runtime logs, screenshots, client binaries, and downloaded game assets outside Git.

## License

[GNU General Public License v3](LICENSE). Preserve third-party copyright and license notices.
