#!/usr/bin/env python3
"""Build the Vitis platform and the bare-metal application.

Usage (from final_project/):
    vitis -s sw/build.py                  # fresh workspace: platform + app
    vitis -s sw/build.py --app-only       # rebuild only the app (workspace must exist)
    vitis -s sw/build.py --xsa path/to/system_top.xsa
    vitis -s sw/build.py --workspace some/other/dir

Workspace goes to build/vitis by default. App sources are linked (not copied) from sw/src,
so edits in sw/src are picked up by the next build and by the Vitis GUI.
"""
import argparse
import os
import shutil
import stat
import sys
import time

import vitis

SW_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR = os.path.dirname(SW_DIR)
BUILD_DIR = os.path.join(ROOT_DIR, "build")

WORKSPACE_DEFAULT = os.path.join(BUILD_DIR, "vitis")
SRC_DIR = os.path.join(SW_DIR, "src")
DEFAULT_XSA = os.path.join(BUILD_DIR, "system_top.xsa")

PLATFORM_NAME = "fmcomms2_platform"
APP_NAME = "app"
CPU = "ps7_cortexa9_0"
DOMAIN_NAME = "standalone_" + CPU
HEAP_SIZE = 0x100000

# The Vitis server keeps the workspace locked for ~1 min after the previous run
LOCK_TIMEOUT_S = 120


def retry_while_locked(action, is_locked):
    deadline = time.monotonic() + LOCK_TIMEOUT_S
    while True:
        try:
            return action()
        except Exception as exc:
            if not is_locked(exc) or time.monotonic() > deadline:
                raise
            print("INFO: workspace is still locked by a previous Vitis run, waiting...")
            time.sleep(5)


def remove_workspace(path):
    # Delete the lock file first: if Vitis (server or IDE) still holds the
    # workspace this fails before anything else is touched
    lock = os.path.join(path, "_ide", ".wsdata", ".lock")
    if os.path.exists(lock):
        try:
            retry_while_locked(
                lambda: os.remove(lock),
                lambda exc: getattr(exc, "winerror", None) == 32)  # file in use
        except PermissionError:
            sys.exit(f"ERROR: workspace {path} is in use. Close the Vitis IDE on it and retry")

    # Vitis copies some files from the install as read-only
    def make_writable(func, p, _exc):
        os.chmod(p, stat.S_IWRITE)
        func(p)
    shutil.rmtree(path, onexc=make_writable)


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xsa", default=DEFAULT_XSA, help="hardware handoff file")
    parser.add_argument("--workspace", default=WORKSPACE_DEFAULT,
                        help="Vitis workspace folder")
    parser.add_argument("--app-only", action="store_true",
                        help="rebuild only the app in the existing workspace")
    # vitis -s may pass extra arguments of its own, so ignore unknown ones
    args, _ = parser.parse_known_args()
    return args


def create_platform(client, xsa):
    platform = client.create_platform_component(
        name=PLATFORM_NAME,
        hw_design=xsa,
        os="standalone",
        cpu=CPU,
        domain_name=DOMAIN_NAME,
    )
    platform.build()
    return platform


def create_app(client, workspace):
    # Pass the exact .xpfm: find_platform_in_repos() can pick an unrelated
    # built-in platform when names overlap
    platform_xpfm = os.path.join(workspace, PLATFORM_NAME, "export",
                                 PLATFORM_NAME, PLATFORM_NAME + ".xpfm")
    app = client.create_app_component(
        name=APP_NAME,
        platform=platform_xpfm,
        domain=DOMAIN_NAME,
    )
    app.import_files(from_loc=SRC_DIR, dest_dir_in_cmp="src",
                     is_skip_copy_sources=True)

    # Every folder with headers under sw/src (app + no-OS drivers)
    include_dirs = sorted({root for root, _, files in os.walk(SRC_DIR)
                           if any(f.endswith(".h") for f in files)})
    app.set_app_config(key="USER_INCLUDE_DIRECTORIES", values=include_dirs)
    # The AD9361 driver allocates its state with malloc; the default heap is 8 KB
    app.set_app_config(key="USER_LINK_OTHER_FLAGS",
                       values=[f"-Wl,--defsym=_HEAP_SIZE={HEAP_SIZE:#x}"])
    return app


def main():
    args = parse_args()
    xsa = os.path.abspath(args.xsa)
    workspace = os.path.abspath(args.workspace)

    if not args.app_only:
        if not os.path.isfile(xsa):
            sys.exit(f"ERROR: XSA not found: {xsa}\n"
                     "Build the hardware first (create_project.tcl -tclargs build)")
        if os.path.isdir(workspace):
            remove_workspace(workspace)
    elif not os.path.isdir(workspace):
        sys.exit(f"ERROR: workspace not found: {workspace}\nRun without --app-only first")

    # build() does not raise on failure, so judge success by a fresh ELF
    elf = os.path.join(workspace, APP_NAME, "build", APP_NAME + ".elf")
    if os.path.isfile(elf):
        os.remove(elf)

    client = vitis.create_client()
    try:
        retry_while_locked(lambda: client.set_workspace(workspace),
                           lambda exc: "already in use" in str(exc))
        if args.app_only:
            app = client.get_component(APP_NAME)
        else:
            create_platform(client, xsa)
            app = create_app(client, workspace)
        app.build()
    finally:
        vitis.dispose()

    if not os.path.isfile(elf):
        sys.exit(f"ERROR: app build failed, see {os.path.dirname(elf)}/build.log")
    print(f"INFO: done -> {elf}")


if __name__ == "__main__":
    main()
