TITLE:
Show HN: Install Playwright's browser deps without root (apt-get download, no sudo)

BODY:
`playwright install --with-deps` and `install-deps` both shell out to
`apt-get install`, which needs root. Without it you get chromium refusing
to launch with something like:

    error while loading shared libraries: libnspr4.so: cannot open shared object file

...and on a stock Ubuntu box that's not one missing library, it's 39:
at-spi2-core, libnss3, libgbm1, a pile of X11/font packages, etc. No
`apt install`, no fix. This hits anyone running Playwright somewhere they
don't own the base image: CI runners, containers, locked-down dev sandboxes,
managed platforms like Render/Replit.

The trick: `apt-get download <pkg>` fetches the .deb with no root required
(it's a HTTP GET plus a local write, not a system mutation), and
`dpkg-deb -x` unpacks *its contents* into any directory you own — same
bytes `apt-get install` would put in /usr/lib, just extracted somewhere
you're allowed to write. So the script:

1. Asks Playwright what it thinks is missing (`install-deps --dry-run`)
2. `apt-get download`s each package into a scratch dir
3. `dpkg-deb -x`s them into a local prefix (default `~/.local/rootless-playwright`)
4. Points the browser at them via `LD_LIBRARY_PATH` and writes an `env.sh` to source

Nothing touches /usr, nothing needs sudo, nothing modifies dpkg's database.
On a clean sandbox, `./install.sh` downloads those 39 packages, extracts
them, installs the chromium binary, and launches it headless to verify —
about 40 seconds end to end.

The obvious pushback is "just use a container/Nix." Sure, if you control
the image — but plenty of Playwright users are *inside* someone else's
container or sandbox already and can't rebuild the base layer. This is for
that case: a userspace fix that doesn't ask for infra changes.

I hit this exact problem this week running Playwright inside a genuinely
no-root sandbox, expected a tool for it to already exist, didn't find one,
so wrote this instead. MIT licensed, ~110 lines of bash.

https://github.com/LooseChangeLabs/rootless-playwright
