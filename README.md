# File Managers for Kindle

Run **Filebrowser** and **Syncthing** services on a jailbroken Kindle, controlled through a native touch UI, or KUAL.

!(screenshot)[assets/filemanagers-screenshot.png]

## Features

- **Filebrowser** — browse, upload and download files on your Kindle from any browser on the same Wi-Fi network. No desktop software required; just open a URL.
- **Syncthing** — continuously synchronise folders between your Kindle and other devices (computers, phones, tablets) connected to the same wifi network. Works in the background with no cloud server.
- **Native Kindle UI** — an Illusion app lets you start and stop both services with a single tap, see their status and access URL in real time.
- **KUAL extension** — if you prefer KUAL, the same controls are available directly from the launcher menu.
- **Boot startup** — optional upstart jobs make both services start automatically every time the Kindle boots.

## Installation

Download the [latest release](https://github.com/kbarni/kindlefilemanagers/releases/latest) from GitHub and extract it.

Connect your Kindle via USB and copy the contents of the release to the **root of the Kindle**:

### (Optional) Install the binaries

The release contains the Linux ARM binaries for *Filebrowser* and *Syncthing*, so it's ready to use. 

If it doesn't work - or you want to update the binary to a newer version, use the links below

| Binary | Where to get it | Destination on Kindle |
|---|---|---|
| `filebrowser` | [github.com/filebrowser/filebrowser](https://github.com/filebrowser/filebrowser/releases) — pick the `linux-arm` build | `/mnt/us/filemanagers/bin/filebrowser` |
| `syncthing` | [github.com/syncthing/syncthing](https://github.com/syncthing/syncthing/releases) — pick the `linux-arm` build | `/mnt/us/filemanagers/bin/syncthing` |

## Launching the app

Use the **File managers** scriptlet from the **Kindle library** to run the full interface.

You can also access the service controls from **KUAL → File Managers**.

## Usage

### Filebrowser

Filebrowser gives you a web-based file manager for the Kindle's storage.

1. In the File Managers app, tap the toggle next to **File Browser** to start it.
2. The status line will show the access URL once it is running, e.g. `http://192.168.1.10:80`.
3. Open that URL in any browser on the same Wi-Fi network.
4. Log in with the default credentials: **admin / admin12345678**.
   Change the password in Filebrowser's Settings after first login.
5. Tap the toggle again to stop Filebrowser when you are done.

For detailed instructions check the [Filebrowser homepage](https://filebrowser.org/)

### Syncthing

Syncthing keeps folders in sync between the Kindle and your other devices.

1. **First-time setup**: check **Start with configuration interface**, then tap the Syncthing toggle. The status line will show the configuration URL, e.g. `http://192.168.1.10:8384`.
2. Open that URL in a browser, then add the folders and remote devices you want to sync, just as you would on any other Syncthing installation.
3. Once configured, uncheck **Start with configuration interface** and use the toggle to start Syncthing in normal daemon mode. The configuration web UI will no longer be accessible from outside the device, which is the recommended mode for day-to-day use.
4. Tap the toggle again to stop Syncthing.

Syncthing data and configuration are stored in `/mnt/us/filemanagers/settings/` and are preserved across restarts.

For detailed instructions check the [Syncthing homepage](https://syncthing.net/)

### Auto-start on boot (optional)

To have Filebrowser and Syncthing start automatically every time the Kindle boots:

1. Open the File Managers app and expand **Advanced settings**.
2. Tap **Install startup services**.

This copies upstart job files to `/etc/upstart/`, which requires a temporary write to the root filesystem. The operation will survive a software update but **will be reverted by a factory reset**.

To remove the auto-start jobs, delete `/etc/upstart/filebrowser.conf` and `/etc/upstart/syncthing.conf` from a shell (requires `mntroot rw` first).

## Troubleshooting

- **Toggle does nothing** — make sure Utild is running. The launcher script starts it automatically; if you opened the app another way, run `documents/filemanagers.sh` from a shell.
- **Binary not found** — verify the filebrowser/syncthing binaries are at the correct paths and are executable (`chmod +x`).
- **Can't reach the web UI** — ensure your Kindle and your computer are on the same Wi-Fi network. Check the log files at `/mnt/us/filemanagers/filebrowser.log` and `/mnt/us/filemanagers/settings/syncthing.log`.
- **Status stuck on "checking…"** — open the app from the library launcher rather than directly, so the status file is initialised.

## Credits

- [Illusion framework](https://github.com/penguins184/Penguins-Kindle-Wiki) by [Penguins184](https://github.com/penguins184)
- [Filebrowser](https://filebrowser.org/) ([Github repo](https://github.com/filebrowser/filebrowser))
- [Syncthing](https://syncthing.net/) ([Github repo](https://github.com/syncthing/syncthing))
- [KOReader Syncthing plugin](https://github.com/arthurrump/syncthing.koplugin) by [Arthur Rump](https://github.com/arthurrump) and [Filebrowser plugin](https://github.com/b-/filebrowser.koplugin) by [Bri](https://github.com/b-) for inspiration.
