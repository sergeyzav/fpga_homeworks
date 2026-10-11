import os
import shutil
import stat
import vitis

SCRIPT_DIR   = os.path.dirname(os.path.abspath(__file__))     # homework_5/sw
PROJECT_DIR  = os.path.dirname(SCRIPT_DIR)                    # homework_5
PROJECT_NAME = os.path.basename(PROJECT_DIR)                  # "homework_5"
ROOT_BUILD   = os.path.abspath(os.path.join(PROJECT_DIR, "..", "build"))
BUILD_DIR    = os.path.join(ROOT_BUILD, PROJECT_NAME)         # fpga_homeworks/build/homework_5
WS           = os.path.join(BUILD_DIR, "ws")
XSA          = os.path.join(PROJECT_DIR, "hw", "microblaze.xsa")   # homework_5/hw/microblaze.xsa
SRC_DIR      = os.path.join(SCRIPT_DIR, "src")

if not os.path.isfile(XSA):
    raise FileNotFoundError(f"XSA не знайдено: {XSA}")

def _force_remove(func, path, _exc):
    os.chmod(path, stat.S_IWRITE)
    func(path)

if os.path.exists(WS):
    shutil.rmtree(WS, onerror=_force_remove)
if os.path.exists(WS):
    raise RuntimeError(
        f"Не вдалося видалити {WS}. Закрийте Vitis/Vivado, що його тримають, "
        f"і видаліть папку вручну.")
os.makedirs(os.path.dirname(WS), exist_ok=True)

client = vitis.create_client()
client.set_workspace(WS)

CPU    = "microblaze_0"
DOMAIN = f"standalone_{CPU}"

plat = client.create_platform_component(
    name="plat", hw_design=XSA, os="standalone", cpu=CPU)
plat.build()

app = client.create_app_component(
    name="app",
    platform=os.path.join(WS, "plat", "export", "plat", "plat.xpfm"),
    domain=DOMAIN)
app.import_files(from_loc=SRC_DIR, files=["main.c"], dest_dir_in_cmp="src")
app.build()

vitis.dispose()