# 2026-10-01T19:55:31.349011300
import vitis

client = vitis.create_client()
client.set_workspace(path="v")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_component")
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

status = platform.update_hw(hw_design = "$COMPONENT_LOCATION/../../design_1_wrapper0.xsa")

status = platform.build()

comp.build()

status = platform.build()

status = platform.build()

comp.build()

component = client.get_component(name="app_component")

lscript = component.get_ld_script(path="C:\Users\sergo\vivprojects\microblaze_test\v\app_component\src\lscript.ld")

lscript.set_stack_size("0x400")

lscript.set_heap_size("0x400")

lscript.set_heap_size("0x200")

status = platform.build()

comp.build()

lscript.set_heap_size("0x100")

status = platform.build()

comp.build()

status = platform.build()

comp.build()

status = platform.build()

comp.build()

lscript.set_stack_size("0x200")

lscript.set_heap_size("0x0")

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

status = platform.build()

comp.build()

vitis.dispose()

