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
via `patch :DATA`) makes spice-gtk, on macOS (GDK_WINDOWING_QUARTZ):

* fetch the guest's clipboard text eagerly when it grabs the clipboard and
  publish it with `gtk_clipboard_set_text()`, which never re-enters the
  main loop, so guest->host copy/paste works without crashing; and
* refuse to run the nested loop in `clipboard_get()`.

## Install

    brew tap neelsani/virt-manager-macos /path/to/this/repo
    brew uninstall spice-gtk virt-viewer   # remove previous installs
    brew install neelsani/virt-manager-macos/virt-viewer

The tap's `virt-viewer` depends on the tap's patched `spice-gtk`, so it is
always used, and the formula builds from source (no bottle).

## Verify

    remote-viewer vv://...  # then Ctrl+C / Ctrl+V inside the guest