#include "include/connectivity_linux/connectivity_linux_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

struct _ConnectivityLinuxPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(ConnectivityLinuxPlugin, connectivity_linux_plugin, g_object_get_type())

static void connectivity_linux_plugin_class_init(ConnectivityLinuxPluginClass *klass) {}

static void connectivity_linux_plugin_init(ConnectivityLinuxPlugin *self) {}

void connectivity_linux_plugin_register_with_registrar(FlPluginRegistrar *registrar) {}
