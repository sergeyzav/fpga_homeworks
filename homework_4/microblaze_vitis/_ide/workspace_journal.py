# 2026-10-02T22:36:24.921449100
import vitis

client = vitis.create_client()
client.set_workspace(path="v")

platform = client.get_component(name="platform")
status = platform.build()

status = platform.build()

comp = client.get_component(name="app_component")
comp.build()

