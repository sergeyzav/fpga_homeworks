import os
import shutil
import vitis

HERE = os.path.dirname(os.path.abspath(__file__))                 # homework_7/hls
SRC  = os.path.join(HERE, "src").replace("\\", "/")
WS   = os.path.join(HERE, "..", "..", "build",
                    os.path.basename(os.path.dirname(HERE)), "hls_ws")

shutil.rmtree(WS, ignore_errors=True)
os.makedirs(WS)

client = vitis.create_client()
client.set_workspace(WS)
client.create_hls_component(name="moving_max",
                            cfg_file=["hls_config.cfg"],
                            template="empty_hls_component")

with open(os.path.join(WS, "moving_max", "hls_config.cfg"), "w") as f:
    f.write(f"""part=xc7z020clg400-1

[hls]
syn.top=moving_max
clock=10
syn.file={SRC}/moving_max.cpp
syn.file={SRC}/moving_max.h
tb.file={SRC}/main_tb.cpp
package.output.format=ip_catalog
""")

comp = client.get_component(name="moving_max")
comp.run(operation="C_SIMULATION")
comp.run(operation="SYNTHESIS")

vitis.dispose()