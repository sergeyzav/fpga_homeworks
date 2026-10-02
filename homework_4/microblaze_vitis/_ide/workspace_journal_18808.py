# 2026-10-01T23:39:18.595287600
import vitis

client = vitis.create_client()
client.set_workspace(path="v")

platform = client.get_component(name="platform")
status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

status = platform.build()

comp.build()

vitis.dispose()

