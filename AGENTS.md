# AGENTS.md

Before working on this repo, read `GEMINI.md`.

`GEMINI.md` contains the AppleSMC key reference, helper command behavior, build commands, and safety notes for this Apple Silicon fan control app.

## Useful Commands

- Build: `./build.sh`
- Install/update local app: `./install.sh`
- Run local build: `open FanControl.app`

## Important Constraints

- Manual fan control uses a privileged setuid helper at `/usr/local/bin/smc-helper`.
- Do not weaken helper validation, helper permissions, or automatic fan restore behavior.
- Preserve watchdog behavior that returns fans to auto mode if the app exits unexpectedly.
- Keep shipped features documented in `README.md`.
