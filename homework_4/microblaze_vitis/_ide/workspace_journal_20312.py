# 2026-10-01T19:12:01.127300900
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

component = client.get_component(name="app_component")

lscript = component.get_ld_script(path="C:\Users\sergo\vivprojects\microblaze_test\v\app_component\src\lscript.ld")

lscript.set_stack_size("0x200")

status = platform.build()

comp.build()

