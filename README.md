homebrew-virt-manager-macos
===========================

Local Homebrew tap with a patched `spice-gtk` that fixes the
`remote-viewer` crash when using Ctrl+C / Ctrl+V against a Windows/Linux
guest on macOS.

## Problem

Copying or pasting inside a guest caused `remote-viewer` to abort with:

```
Gdk:ERROR:../gdk/quartz/gdkeventloop-quartz.c:585:select_thread_collect_poll:
assertion failed: (ufds[i].fd == current_pollfds[i].fd)
```

Root cause: spice-gtk serves the host clipboard lazily from
`clipboard_get()`, which blocks in a **nested GMainLoop** while waiting for
the guest agent. On macOS GTK invokes that callback from inside an
NSPasteboard owner callback, and the nested loop corrupts GDK Quartz's
select-thread poll state machine, aborting the process.

See https://gitlab.freedesktop.org/spice/spice-gtk/-/issues/80 and
https://github.com/jeffreywildman/homebrew-virt-manager/issues/118,
https://github.com/jeffreywildman/homebrew-virt-manager/issues/206

## Fix

`patches/spice-gtk-macos-clipboard.patch` (also inlined in `spice-gtk.rb`
via `patch :DATA`) makes spice-gtk work on macOS (GDK_WINDOWING_QUARTZ):

* **guest->host** — when the guest grabs the clipboard, fetch its text eagerly
  and publish it with `gtk_clipboard_set_text()`, which never re-enters the
  main loop (the nested-loop `clipboard_get()` corrupted GDK Quartz's
  select-thread poll state and aborted the process); and refuse to run the
  nested loop in `clipboard_get()`.
* **host->guest** — GTK never emits `GtkClipboard::owner-change` on macOS
  (gnome/gtk#1757), so spice-gtk never noticed host clipboard changes. A
  ~300ms pasteboard poll detects external changes and grabs the host clipboard
  to the guest agent, so copying on the Mac and pasting in the guest works too.

## Install

    brew tap neelsani/virt-manager-macos https://github.com/neelsani/homebrew-virt-manager-macos
    brew trust neelsani/virt-manager-macos   # Homebrew 6 requires trusting taps
    brew uninstall spice-gtk virt-viewer    # remove previous installs
    brew install neelsani/virt-manager-macos/virt-viewer

The tap's `virt-viewer` depends on the tap's patched `spice-gtk`, so it is
always used, and the formula builds from source (no bottle).

## Disabling clipboard sharing (privacy)

To stop the Mac clipboard from ever being shared with the guest (e.g. so a
password copied on the Mac can't leak into the VM), pass `--spice-disable-clipboard`.
It is a real spice-gtk option added in this tap (not in upstream 0.42), and it
forces `auto-clipboard` off in both directions.

```sh
# direct
remote-viewer --spice-disable-clipboard vv://...

# incus VGA console
incus default set console_spice_command="remote-viewer --spice-disable-clipboard SOCKET"
# re-enable: incus default unset console_spice_command
```

## Verify

    remote-viewer vv://...  # then Ctrl+C / Ctrl+V inside the guest