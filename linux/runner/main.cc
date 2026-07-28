#include "my_application.h"

// Flutter's desktop embedder reads engine switches from environment variables,
// not from the Dart entrypoint argument list. Append the software-rendering
// switch while preserving switches supplied by `flutter run` (VM service,
// profiling, and so on).
static void append_engine_switch(const gchar* requested_switch) {
  const gchar* count_value = g_getenv("FLUTTER_ENGINE_SWITCHES");
  guint count = count_value == nullptr
                    ? 0
                    : g_ascii_strtoull(count_value, nullptr, 10);

  for (guint i = 1; i <= count; i++) {
    g_autofree gchar* key = g_strdup_printf("FLUTTER_ENGINE_SWITCH_%u", i);
    const gchar* value = g_getenv(key);
    if (g_strcmp0(value, requested_switch) == 0) {
      return;
    }
  }

  count++;
  g_autofree gchar* key = g_strdup_printf("FLUTTER_ENGINE_SWITCH_%u", count);
  g_autofree gchar* updated_count = g_strdup_printf("%u", count);
  g_setenv(key, requested_switch, TRUE);
  g_setenv("FLUTTER_ENGINE_SWITCHES", updated_count, TRUE);
}

static gchar* find_engine_switch(const gchar* requested_switch) {
  const gchar* count_value = g_getenv("FLUTTER_ENGINE_SWITCHES");
  guint count = count_value == nullptr
                    ? 0
                    : g_ascii_strtoull(count_value, nullptr, 10);
  for (guint i = 1; i <= count; i++) {
    g_autofree gchar* key = g_strdup_printf("FLUTTER_ENGINE_SWITCH_%u", i);
    const gchar* value = g_getenv(key);
    if (g_strcmp0(value, requested_switch) == 0) {
      return g_strdup(value);
    }
  }
  return g_strdup("not-found");
}

int main(int argc, char** argv) {
  // Force Mesa onto its CPU implementation as a second layer of protection
  // against broken host/VM GPU acceleration.
  g_setenv("LIBGL_ALWAYS_SOFTWARE", "true", TRUE);
  g_setenv("GALLIUM_DRIVER", "llvmpipe", TRUE);
  g_setenv("MESA_LOADER_DRIVER_OVERRIDE", "llvmpipe", TRUE);
  g_setenv("LIBGL_DRI3_DISABLE", "true", TRUE);
  g_setenv("vblank_mode", "0", TRUE);
  // This is the Linux embedder's authoritative compositor selector. It makes
  // FlView use the Cairo/software compositor instead of creating an OpenGL
  // view, regardless of the host GPU and desktop session.
  g_setenv("FLUTTER_LINUX_RENDERER", "software", TRUE);
  append_engine_switch("enable-software-rendering=true");
  append_engine_switch("enable-impeller=false");

  g_autofree gchar* software_switch =
      find_engine_switch("enable-software-rendering=true");
  g_autofree gchar* impeller_switch =
      find_engine_switch("enable-impeller=false");
  g_message("NAZA renderer: software rendering ENABLED (%s, %s)",
            software_switch, impeller_switch);
  g_message("NAZA renderer: FLUTTER_LINUX_RENDERER=%s, LIBGL_ALWAYS_SOFTWARE=%s, GALLIUM_DRIVER=%s, MESA=%s",
            g_getenv("FLUTTER_LINUX_RENDERER"),
            g_getenv("LIBGL_ALWAYS_SOFTWARE"), g_getenv("GALLIUM_DRIVER"),
            g_getenv("MESA_LOADER_DRIVER_OVERRIDE"));

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
