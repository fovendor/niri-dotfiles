#!/usr/bin/env python3
import json
import os
import re
import subprocess
import sys


def niri_msg(*args, json_output=False, check=False):
    cmd = ["niri", "msg"]
    if json_output:
        cmd.append("-j")
    cmd.extend(args)

    proc = subprocess.run(cmd, text=True, capture_output=True)
    if check and proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, proc.stdout, proc.stderr)
    return proc


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


def current_column(windows, focused):
    focused_x = focused.get("layout", {}).get("pos_in_scrolling_layout", [None])[0]
    if focused_x is None:
        return None, []

    columns = sorted(
        {
            window.get("layout", {}).get("pos_in_scrolling_layout", [None])[0]
            for window in windows
            if not window.get("is_floating")
            and window.get("workspace_id") == focused.get("workspace_id")
            and window.get("layout", {}).get("pos_in_scrolling_layout")
        }
    )
    return focused_x, columns


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
    if not output_name:
        return None

    logical = outputs.get(output_name, {}).get("logical")
    if not logical:
        return None

    return logical.get("width")


def tile_width(window):
    tile_size = window.get("layout", {}).get("tile_size")
    if not tile_size:
        return None
    return int(round(tile_size[0]))


def nearest_preset_index(window, presets, width):
    window_width = tile_width(window)
    if window_width is None or width is None or width <= 0:
        return None

    ratio = window_width / width
    return min(range(len(presets)), key=lambda idx: abs(presets[idx] - ratio))


def main():
    focused = load_json("focused-window")
    windows = load_json("windows")
    presets = preset_column_widths()

    if not focused or not windows or focused.get("is_floating"):
        return action("switch-preset-column-width").returncode

    focused_id = str(focused["id"])
    focused_x, columns = current_column(windows, focused)

    if focused_x not in columns:
        return action("switch-preset-column-width").returncode

    index = columns.index(focused_x)
    if index + 1 < len(columns):
        neighbor_action = "focus-column-right"
    elif index > 0:
        neighbor_action = "focus-column-left"
    else:
        return action("switch-preset-column-width").returncode

    action("switch-preset-column-width")
    focused_after_resize = load_json("focused-window")
    if not focused_after_resize:
        return 0

    width = output_width(focused_after_resize.get("workspace_id"))
    focused_preset = nearest_preset_index(focused_after_resize, presets, width)
    if focused_preset is None:
        return 0

    target_width = 1.0 - presets[focused_preset]
    target_preset = min(range(len(presets)), key=lambda idx: abs(presets[idx] - target_width))

    focus_neighbor = action(neighbor_action)
    if focus_neighbor.returncode == 0:
        for _ in range(len(presets) + 1):
            neighbor = load_json("focused-window")
            if nearest_preset_index(neighbor, presets, width) == target_preset:
                break
            action("switch-preset-column-width")
    action("focus-window", "--id", focused_id)

    return 0


if __name__ == "__main__":
    sys.exit(main())
