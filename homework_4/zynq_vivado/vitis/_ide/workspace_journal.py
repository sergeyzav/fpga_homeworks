# 2026-09-28T21:54:50.005486200
import vitis

client = vitis.create_client()
client.set_workspace(path="vitis")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

platform = client.create_platform_component(name = "platform2",hw_design = "$COMPONENT_LOCATION/../../led_blinker_wrapper.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

comp = client.get_component(name="app_component")
status = comp.update_platform(platform="$COMPONENT_LOCATION/../platform2/export/platform2/platform2.xpfm")

platform = client.get_component(name="platform2")
status = platform.build()

comp = client.get_component(name="app_component")
status = comp.clean()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

comp = client.create_app_component(name="app_component2",platform = "$COMPONENT_LOCATION/../platform2/export/platform2/platform2.xpfm",domain = "standalone_ps7_cortexa9_0")

status = platform.build()

comp = client.get_component(name="app_component2")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

