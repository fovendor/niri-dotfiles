#!/usr/bin/env python3
import json
import os
import re
import socket
import subprocess
import sys


def niri_msg(*args, json_output=False):
    cmd = ["niri", "msg"]
    if json_output:
        cmd.append("-j")
    cmd.extend(args)
    return subprocess.run(cmd, text=True, capture_output=True)


def action(*args):
    return niri_msg("action", *args)


def load_json(*args):
    proc = niri_msg(*args, json_output=True)
    if proc.returncode != 0:
        return None

    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        return None


def workspace_columns(windows, focused):
    columns = {}
    for window in windows:
        position = window.get("layout", {}).get("pos_in_scrolling_layout")
        if (
            window.get("is_floating")
            or window.get("workspace_id") != focused.get("workspace_id")
            or not position
        ):
            continue
        columns.setdefault(position[0], []).append(window)

    return sorted(columns.items())


def nearest_neighbor(windows, focused):
    position = focused.get("layout", {}).get("pos_in_scrolling_layout")
    if not position:
        return None

    focused_x = position[0]
    columns = workspace_columns(windows, focused)
    column_positions = [column_x for column_x, _ in columns]
    if focused_x not in column_positions:
        return None

    index = column_positions.index(focused_x)
    if index + 1 < len(columns):
        neighbor_windows = columns[index + 1][1]
    elif index > 0:
        neighbor_windows = columns[index - 1][1]
    else:
        return None

    # Width is a property of the whole column, so any window id in it can target it.
    return min(
        neighbor_windows,
        key=lambda window: window.get("layout", {}).get(
            "pos_in_scrolling_layout", [0, 0]
        )[1],
    )


def preset_column_widths():
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    config_path = os.path.join(config_home, "niri", "config.kdl")

    presets = []
    in_preset_block = False

    try:
        with open(config_path, encoding="utf-8") as config:
            for line in config:
                if re.match(r"\s*preset-column-widths\s*\{", line):
                    in_preset_block = True
                    continue
                if in_preset_block and re.match(r"\s*\}", line):
                    break

                if in_preset_block:
                    match = re.match(r"\s*proportion\s+([0-9.]+)\b", line)
                    if match:
                        presets.append(float(match.group(1)))
    except OSError:
        pass

    return presets or [0.33333, 0.5, 0.66667]


def output_width(workspace_id):
    workspaces = load_json("workspaces")
    outputs = load_json("outputs")
    if not workspaces or not outputs:
        return None

    output_name = next(
        (
            workspace.get("output")
            for workspace in workspaces
            if workspace.get("id") == workspace_id
        ),
        None,
    )
    logical = outputs.get(output_name, {}).get("logical") if output_name else None
    return logical.get("width") if logical else None


def tile_width(window):
    tile_size = window.get("layout", {}).get("tile_size")
    return float(tile_size[0]) if tile_size else None


def next_preset(window, presets, width):
    current_width = tile_width(window)
    if current_width is None or width is None or width <= 0:
        return None

    current_ratio = current_width / width
    current_index = min(
        range(len(presets)), key=lambda index: abs(presets[index] - current_ratio)
    )
    return presets[(current_index + 1) % len(presets)]


def width_request(window_id, proportion):
    return {
        "Action": {
            "SetWindowWidth": {
                "id": int(window_id),
                # niri-ipc represents proportions as percentages (50.0 means 50%).
                "change": {"SetProportion": proportion * 100},
            }
        }
    }


def send_widths_over_ipc(widths):
    """Queue all width changes before waiting for any reply.

    niri handles one regular request per socket. Connecting every socket first and
    sending all requests before reading replies lets the compositor start both
    animations in the same render cycle, without changing focus in between.
    """
    socket_path = os.environ.get("NIRI_SOCKET")
    if not socket_path:
        return False

    connections = []
    try:
        for _ in widths:
            connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            connection.settimeout(2)
            connection.connect(socket_path)
            connections.append(connection)

        for connection, (window_id, proportion) in zip(connections, widths):
            payload = json.dumps(
                width_request(window_id, proportion), separators=(",", ":")
            )
            connection.sendall((payload + "\n").encode())

        succeeded = True
        for connection in connections:
            response = b""
            while not response.endswith(b"\n"):
                chunk = connection.recv(4096)
                if not chunk:
                    break
                response += chunk
            try:
                succeeded = succeeded and "Ok" in json.loads(response)
            except (json.JSONDecodeError, UnicodeDecodeError):
                succeeded = False
        return succeeded
    except OSError:
        return False
    finally:
        for connection in connections:
            connection.close()


def send_widths_with_cli(widths):
    # This fallback still launches both changes before waiting for either one.
    processes = [
        subprocess.Popen(
            [
                "niri",
                "msg",
                "action",
                "set-window-width",
                "--id",
                str(window_id),
                f"{proportion * 100:.8g}%",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        for window_id, proportion in widths
    ]
    return max(process.wait() for process in processes)


def main():
    focused = load_json("focused-window")
    windows = load_json("windows")
    presets = preset_column_widths()

    if not focused or not windows or focused.get("is_floating"):
        return action("switch-preset-column-width").returncode

    neighbor = nearest_neighbor(windows, focused)
    if neighbor is None:
        return action("switch-preset-column-width").returncode

    width = output_width(focused.get("workspace_id"))
    focused_proportion = next_preset(focused, presets, width)
    if focused_proportion is None:
        return action("switch-preset-column-width").returncode

    widths = [
        (focused["id"], focused_proportion),
        (neighbor["id"], 1.0 - focused_proportion),
    ]
    if send_widths_over_ipc(widths):
        return 0
    return send_widths_with_cli(widths)


if __name__ == "__main__":
    sys.exit(main())
