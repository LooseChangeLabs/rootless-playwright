# rootless-playwright

Install Playwright's browser system dependencies **without root**.

## The problem

`npx playwright install --with-deps` and `npx playwright install-deps` both
shell out to `apt-get install`, which needs root. That's fine on your laptop,
but it fails outright in a lot of places people actually run Playwright:

- Containers and CI runners without passwordless sudo
- Locked-down dev sandboxes (Codespaces-style environments, AI coding agent
  sessions, restricted CI images)
- Managed platforms like Render, Replit, or Streamlit Cloud where you don't
  control the base image

The error is always some variant of:

```
error while loading shared libraries: libnspr4.so: cannot open shared object file
```

...followed by a wall of 30-40 missing `.so` files, and no way to `apt install`
them.

## The fix

Turns out you don't need `apt-get install` to get files off of Ubuntu's
package mirrors — `apt-get download` fetches a `.deb` with no root required,
and `dpkg-deb -x` unpacks its contents into any directory you own. So:

1. Ask Playwright what packages it thinks are missing (`playwright
   install-deps --dry-run`).
2. `apt-get download` each one into a scratch directory.
3. `dpkg-deb -x` them into a local prefix (default: `~/.local/rootless-playwright`).
4. Point the browser at the extracted `.so` files via `LD_LIBRARY_PATH`.

Nothing is installed system-wide, nothing needs sudo, and it's trivially
reversible — delete the prefix directory and you're back to normal.

## Usage

```bash
./install.sh                      # chromium, default prefix
./install.sh firefox               # different browser
./install.sh chromium /opt/libs    # custom prefix
```

On success it writes `<prefix>/env.sh` — source it (or add it to your shell
profile / CI setup step) and Playwright will find the libraries every time:

```bash
source ~/.local/rootless-playwright/env.sh
```

## Requirements

- Debian/Ubuntu-based system with `apt-get` and `dpkg-deb` (both present by
  default — no extra install needed)
- Node.js + `npx` (you already need this for Playwright itself)

## Why this is safe

Every step operates on files you own, in a directory you chose. Nothing
touches `/usr`, nothing needs `sudo`, and nothing modifies system package
state. It's the same content `apt-get install` would have written to `/usr/lib`,
just placed somewhere you don't need root to write to.

## License

MIT
