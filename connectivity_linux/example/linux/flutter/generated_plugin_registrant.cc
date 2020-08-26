//
//  Generated file. Do not edit.
//

#include "generated_plugin_registrant.h"

#include <connectivity_linux/connectivity_linux_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) connectivity_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ConnectivityLinuxPlugin");
  connectivity_linux_plugin_register_with_registrar(connectivity_linux_registrar);
}
