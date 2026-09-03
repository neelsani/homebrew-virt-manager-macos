class SpiceGtk < Formula
  include Language::Python::Virtualenv

  desc "GTK client/libraries for SPICE (macOS clipboard crash fix)"
  homepage "https://www.spice-space.org"
  url "https://www.spice-space.org/download/gtk/spice-gtk-0.42.tar.xz"
  sha256 "9380117f1811ad1faa1812cb6602479b6290d4a0d8cc442d44427f7f6c0e7a58"
  license all_of: ["GPL-2.0-or-later", "LGPL-2.1-or-later", "BSD-3-Clause"]
  revision 6

  livecheck do
    url "https://www.spice-space.org/download/gtk/"
    regex(/href=.*?spice-gtk[._-]v?(\d+(?:\.\d+)+)\.t/i)
  end

  # No bottle on purpose: the pre-built bottles would lack the macOS
  # clipboard patch below, so this formula always builds from source.

  depends_on "gettext" => :build
  depends_on "gobject-introspection" => :build
  depends_on "meson" => :build
  depends_on "ninja" => :build
  depends_on "pkgconf" => [:build, :test]
  depends_on "python@3.14" => :build
  depends_on "vala" => :build

  depends_on "cairo"
  depends_on "gdk-pixbuf"
  depends_on "glib"
  depends_on "gstreamer"
  depends_on "gtk+3"
  depends_on "jpeg-turbo"
  depends_on "json-glib"
  depends_on "libepoxy"
  depends_on "libsoup"
  depends_on "libusb"
  depends_on "libx11"
  depends_on "lz4"
  depends_on "openssl@3"
  depends_on "opus"
  depends_on "phodav"
  depends_on "pixman"
  depends_on "spice-protocol"
  depends_on "usbredir"

  on_macos do
    depends_on "gettext"
    depends_on "gobject-introspection"
    depends_on "harfbuzz"
  end

  on_linux do
    depends_on "cyrus-sasl"
    depends_on "libva"
    depends_on "wayland"
    depends_on "zlib-ng-compat"
  end

  pypi_packages package_name:   "",
                extra_packages: "pyparsing"

  resource "pyparsing" do
    url "https://files.pythonhosted.org/packages/f3/91/9c6ee907786a473bf81c5f53cf703ba0957b23ab84c264080fb5a450416f/pyparsing-3.3.2.tar.gz"
    sha256 "c777f4d763f140633dcb6d8a3eda953bf7a214dc4eff598413c070bcdc117cbc"
  end

  # Backport fix for "ld: unknown file type in '.../spice-gtk-0.42/src/spice-glib-sym-file'"
  patch do
    url "https://gitlab.freedesktop.org/spice/spice-gtk/-/commit/1511f0ad5ea67b4657540c631e3a8c959bb8d578.diff"
    sha256 "67c2b1d9c689dbb8eb3ed7c92996cf8c9d083d51050883593ee488957ad2a083"
    type :backport
    resolves "https://gitlab.freedesktop.org/spice/spice-gtk/-/merge_requests/119"
  end

  # Backport six removal
  patch do
    url "https://gitlab.freedesktop.org/spice/spice-common/-/commit/91fc091358ac4906a05b68d70e9db94082c0749f.diff"
    sha256 "dd5ef8701bc1d97c0ff20af9ff95dffc660a5e1a3a8a0a92cd4d643d0a3553ed"
    type :backport
    resolves "https://gitlab.freedesktop.org/spice/spice-common/-/merge_requests/63"
    directory "subprojects/spice-common"
  end
  patch do
    url "https://gitlab.freedesktop.org/spice/spice-common/-/commit/29dacb5f53f5183fb089a3fb02d081dd08bde8a1.diff"
    sha256 "3c8a0adaf4b088986bef7541ffef399c7652969c5584c4a4c4055f4988ef0f7a"
    type :backport
    resolves "https://gitlab.freedesktop.org/spice/spice-common/-/merge_requests/63"
    directory "subprojects/spice-common"
  end

  # https://gitlab.com/keycodemap/keycodemapdb/-/merge_requests/18
  patch :DATA

  def install
    venv = virtualenv_create(buildpath/"venv", "python3.14")
    venv.pip_install resources
    ENV.prepend_path "PATH", venv.root/"bin"

    system "meson", "setup", "build", *std_meson_args
    system "meson", "compile", "-C", "build"
    system "meson", "install", "-C", "build"
  end

  test do
    (testpath/"test.cpp").write <<~CPP
      #include <spice-client.h>
      #include <spice-client-gtk.h>
      int main() {
        return spice_session_new() ? 0 : 1;
      }
    CPP
    ENV.prepend_path "PKG_CONFIG_PATH", "#{Formula["icu4c"].lib}/pkgconfig"
    system ENV.cc, "test.cpp",
                   *shell_output("pkgconf --cflags --libs spice-client-gtk-3.0").chomp.split,
                   "-o", "test"
    system "./test"
  end
end

__END__
diff --git a/subprojects/keycodemapdb/tools/keymap-gen b/subprojects/keycodemapdb/tools/keymap-gen
index b6cc95b..d05e945 100755
--- a/subprojects/keycodemapdb/tools/keymap-gen
+++ b/subprojects/keycodemapdb/tools/keymap-gen
@@ -1,4 +1,4 @@
-#!/usr/bin/python3
+#!/usr/bin/env python3
 # -*- python -*-
 #
 # Keycode Map Generator
diff --git a/src/spice-gtk-session.c b/src/spice-gtk-session.c
index 72b0168..4eb24ed 100644
--- a/src/spice-gtk-session.c
+++ b/src/spice-gtk-session.c
@@ -19,6 +19,19 @@
 #include <glib.h>
 #include <gdk/gdk.h>
 
+#ifdef GDK_WINDOWING_QUARTZ
+#include <gdk/gdkquartz.h>
+#endif
+
+#ifdef GDK_WINDOWING_QUARTZ
+/* Interval (ms) for polling the host pasteboard for host->guest sync.
+ * macOS GTK never emits GtkClipboard::owner-change (gtk#1757), so we detect
+ * host clipboard changes ourselves instead.
+ */
+#define MACOS_CLIPBOARD_POLL_INTERVAL_MS 300
+static gboolean macos_clipboard_poll(gpointer user_data);
+#endif
+
 #ifdef HAVE_X11_XKBLIB_H
 #include <X11/XKBlib.h>
 #endif
@@ -65,6 +78,9 @@ struct _SpiceGtkSessionPrivate {
     gboolean                clip_grabbed[CLIPBOARD_LAST];
     gboolean                clipboard_by_guest[CLIPBOARD_LAST];
     guint                   clipboard_release_delay[CLIPBOARD_LAST];
+    guint                   clipboard_macos_handler[CLIPBOARD_LAST];
+    gchar                   *macos_last_host_text[CLIPBOARD_LAST];
+    guint                   macos_clipboard_poll_source;
     /* TODO: maybe add a way of restoring this? */
     GHashTable              *cb_shared_files;
     /* auto-usbredir related */
@@ -209,6 +225,11 @@ static void spice_gtk_session_init(SpiceGtkSession *self)
     s->clipboard_primary = gtk_clipboard_get(GDK_SELECTION_PRIMARY);
     g_signal_connect(G_OBJECT(s->clipboard_primary), "owner-change",
                      G_CALLBACK(clipboard_owner_change), self);
+#ifdef GDK_WINDOWING_QUARTZ
+    s->macos_clipboard_poll_source =
+        g_timeout_add_full(G_PRIORITY_DEFAULT, MACOS_CLIPBOARD_POLL_INTERVAL_MS,
+                           macos_clipboard_poll, self, NULL);
+#endif
     spice_g_signal_connect_object(keymap, "state-changed",
                                   G_CALLBACK(keymap_modifiers_changed), self, 0);
 }
@@ -266,6 +287,17 @@ static void spice_gtk_session_dispose(GObject *gobject)
     }
     g_clear_pointer(&s->cb_shared_files, g_hash_table_destroy);
 
+#ifdef GDK_WINDOWING_QUARTZ
+    if (s->macos_clipboard_poll_source != 0) {
+        g_source_remove(s->macos_clipboard_poll_source);
+        s->macos_clipboard_poll_source = 0;
+    }
+    for (int i = 0; i < CLIPBOARD_LAST; ++i) {
+        g_free(s->macos_last_host_text[i]);
+        s->macos_last_host_text[i] = NULL;
+    }
+#endif
+
     /* Chain up to the parent class */
     if (G_OBJECT_CLASS(spice_gtk_session_parent_class)->dispose)
         G_OBJECT_CLASS(spice_gtk_session_parent_class)->dispose(gobject);
@@ -299,6 +331,8 @@ static void spice_gtk_session_finalize(GObject *gobject)
     for (i = 0; i < CLIPBOARD_LAST; ++i) {
         g_clear_pointer(&s->clip_targets[i], g_free);
         clipboard_release_delay_remove(self, i, true);
+        if (s->clipboard_macos_handler[i] != 0 && s->main != NULL)
+            g_signal_handler_disconnect(s->main, s->clipboard_macos_handler[i]);
         g_clear_pointer(&s->atoms[i], g_free);
         s->n_atoms[i] = 0;
     }
@@ -858,6 +892,19 @@ static void clipboard_get(GtkClipboard *clipboard,
     g_return_if_fail(info < SPICE_N_ELEMENTS(atom2agent));
     g_return_if_fail(s->main != NULL);
 
+#ifdef GDK_WINDOWING_QUARTZ
+    /* On macOS GTK serves pasteboard requests from inside an NSPasteboard
+     * owner callback. Running the nested GMainLoop below from there corrupts
+     * GDK's select-thread poll state and aborts with
+     *   gdkeventloop-quartz.c:select_thread_collect_poll: assertion failed
+     * (spice-gtk#80, jeffreywildman/homebrew-virt-manager#118/#206).
+     * Clipboard grabs are published with gtk_clipboard_set_text() instead, so
+     * this callback must never spin its own loop on macOS.
+     */
+    if (GDK_IS_QUARTZ_DISPLAY(gdk_display_get_default()))
+        return;
+#endif
+
     if (s->clipboard_release_delay[selection]) {
         SPICE_DEBUG("not requesting data from guest during delayed release");
         return;
@@ -909,6 +956,152 @@ static void clipboard_clear(GtkClipboard *clipboard, gpointer user_data)
        don't need to do anything here */
 }
 
+#ifdef GDK_WINDOWING_QUARTZ
+/* macOS clipboard handling.
+ *
+ * spice-gtk's default clipboard path uses gtk_clipboard_set_with_owner() and
+ * serves data from clipboard_get(), which blocks in a nested GMainLoop while
+ * waiting for the guest agent. On macOS that callback runs inside an
+ * NSPasteboard owner callback (GtkClipboardOwner provideDataForType:), and the
+ * nested loop breaks GDK Quartz's select-thread poll state machine, aborting
+ * the process (see clipboard_get() above).
+ *
+ * Instead, when the guest grabs the clipboard we eagerly request the UTF-8
+ * text and publish it with gtk_clipboard_set_text(), which stores the bytes in
+ * the pasteboard and never re-enters the main loop. Pasting into any host app
+ * then works, and nothing crashes.
+ */
+static void clipboard_macos_set_text(SpiceGtkSession *self, guint selection,
+                                     const guchar *data, guint size)
+{
+    SpiceGtkSessionPrivate *s = self->priv;
+    GtkClipboard *cb;
+    gchar *text;
+    gchar *conv = NULL;
+
+    if (data == NULL || size == 0) {
+        SPICE_DEBUG("clipboard: macOS ignoring empty clipboard from guest");
+        return;
+    }
+
+    text = g_strndup((const gchar *)data, size);
+    if (spice_main_channel_agent_test_capability(s->main, VD_AGENT_CAP_GUEST_LINEEND_CRLF)) {
+        conv = spice_dos2unix(text, size);
+        if (conv != NULL) {
+            g_free(text);
+            text = conv;
+        }
+    }
+
+    cb = get_clipboard_from_selection(s, selection);
+    if (cb != NULL) {
+        SPICE_DEBUG("clipboard: macOS publishing %zu bytes to host clipboard",
+                    strlen(text));
+        gtk_clipboard_set_text(cb, text, -1);
+
+        /* Remember what we published so the host->guest poll below can tell
+         * our own writes apart from real external clipboard changes. */
+        g_free(s->macos_last_host_text[selection]);
+        s->macos_last_host_text[selection] = g_strdup(text);
+    }
+    g_free(text);
+}
+
+/* Host->guest clipboard on macOS.
+ *
+ * spice-gtk normally learns about host clipboard changes from
+ * GtkClipboard::owner-change, but GTK never emits that event on Quartz
+ * (gnome/gtk#1757). Without it spice-gtk never grabs the host clipboard to the
+ * guest agent, so copying on the Mac and pasting in the guest does nothing.
+ *
+ * We work around it by polling: every MACOS_CLIPBOARD_POLL_INTERVAL_MS we
+ * asynchronously read the host pasteboard text and, when it differs from what
+ * we last published/saw, drive the same code path as owner-change(NEW_OWNER)
+ * to grab the host clipboard to the guest.
+ */
+static void macos_clipboard_compare_cb(GtkClipboard *clipboard,
+                                       const gchar *text,
+                                       gpointer user_data)
+{
+    SpiceGtkSession *self = free_weak_ref(user_data);
+    SpiceGtkSessionPrivate *s;
+    const gchar *last;
+    int selection;
+
+    if (self == NULL)
+        return;
+
+    s = self->priv;
+    selection = get_selection_from_clipboard(s, clipboard);
+    if (selection == -1)
+        return;
+
+    if (s->main == NULL || text == NULL)
+        return;
+
+    last = s->macos_last_host_text[selection];
+    if (last != NULL && strcmp(last, text) == 0)
+        return; /* no external change */
+
+    g_free(s->macos_last_host_text[selection]);
+    s->macos_last_host_text[selection] = g_strdup(text);
+
+    SPICE_DEBUG("clipboard: macOS host clipboard changed, grabbing to guest");
+
+    s->clipboard_by_guest[selection] = FALSE;
+    s->clip_hasdata[selection] = TRUE;
+
+    if (s->auto_clipboard_enable && !read_only(self)) {
+        /* clipboard_get_targets() maps the host targets and sends a grab to
+         * the agent, which makes the guest pick up the new host contents. */
+        gtk_clipboard_request_targets(clipboard, clipboard_get_targets,
+                                      get_weak_ref(self));
+    }
+}
+
+static gboolean macos_clipboard_poll(gpointer user_data)
+{
+    SpiceGtkSession *self = user_data;
+    SpiceGtkSessionPrivate *s = self->priv;
+    GtkClipboard *cb;
+
+    if (s->main == NULL || gdk_display_get_default() == NULL)
+        return G_SOURCE_CONTINUE;
+
+    if (!s->auto_clipboard_enable || read_only(self))
+        return G_SOURCE_CONTINUE;
+
+    cb = get_clipboard_from_selection(s, VD_AGENT_CLIPBOARD_SELECTION_CLIPBOARD);
+    if (cb == NULL)
+        return G_SOURCE_CONTINUE;
+
+    gtk_clipboard_request_text(cb, macos_clipboard_compare_cb, get_weak_ref(self));
+
+    return G_SOURCE_CONTINUE;
+}
+
+static void clipboard_macos_got_from_guest(SpiceMainChannel *main, guint selection,
+                                           guint type, const guchar *data, guint size,
+                                           gpointer user_data)
+{
+    SpiceGtkSession *self = user_data;
+    SpiceGtkSessionPrivate *s = self->priv;
+
+    /* One-shot handler; a newer grab re-arms it. */
+    if (s->clipboard_macos_handler[selection] != 0) {
+        g_signal_handler_disconnect(s->main, s->clipboard_macos_handler[selection]);
+        s->clipboard_macos_handler[selection] = 0;
+    }
+
+    if (type != VD_AGENT_CLIPBOARD_UTF8_TEXT) {
+        SPICE_DEBUG("clipboard: macOS ignoring unsupported type %u", type);
+        return;
+    }
+
+    clipboard_macos_set_text(self, selection, data, size);
+}
+#endif /* GDK_WINDOWING_QUARTZ */
+
 static gboolean clipboard_grab(SpiceMainChannel *main, guint selection,
                                guint32* types, guint32 ntypes,
                                gpointer user_data)
@@ -959,6 +1152,29 @@ static gboolean clipboard_grab(SpiceMainChannel *main, guint selection,
         return TRUE;
     }
 
+#ifdef GDK_WINDOWING_QUARTZ
+    if (GDK_IS_QUARTZ_DISPLAY(gdk_display_get_default())) {
+        /* See clipboard_macos_set_text() above: on macOS we cannot serve the
+         * host clipboard lazily through clipboard_get() because that would run
+         * a nested GMainLoop inside an NSPasteboard callback. Fetch the guest's
+         * text up front and publish it with gtk_clipboard_set_text().
+         */
+        if (s->clipboard_macos_handler[selection] != 0) {
+            g_signal_handler_disconnect(s->main, s->clipboard_macos_handler[selection]);
+        }
+        s->clipboard_macos_handler[selection] =
+            g_signal_connect(s->main, "main-clipboard-selection",
+                             G_CALLBACK(clipboard_macos_got_from_guest), self);
+
+        s->clipboard_by_guest[selection] = TRUE;
+        s->clip_hasdata[selection] = FALSE;
+
+        spice_main_channel_clipboard_selection_request(s->main, selection,
+                                                       VD_AGENT_CLIPBOARD_UTF8_TEXT);
+        return TRUE;
+    }
+#endif
+
     if (!gtk_clipboard_set_with_owner(cb,
                                       targets,
                                       num_targets,
