# 2026-10-03T00:52:53.205731900
import vitis

client = vitis.create_client()
client.set_workspace(path="zynq_vitis")

platform = client.create_platform_component(name = "platform",hw_design = "$COMPONENT_LOCATION/../../zynq_vivado/led_blinker_wrapper.xsa",os = "standalone",cpu = "ps7_cortexa9_0",domain_name = "standalone_ps7_cortexa9_0",compiler = "gcc")

comp = client.create_app_component(name="app_component",platform = "$COMPONENT_LOCATION/../platform/export/platform/platform.xpfm",domain = "standalone_ps7_cortexa9_0")

comp = client.get_component(name="app_component")
status = comp.import_files(from_loc="", files=["C:\Users\sergo\vivprojects\microblaze_test\v\app_component\src\main.c"], is_skip_copy_sources = False)

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

