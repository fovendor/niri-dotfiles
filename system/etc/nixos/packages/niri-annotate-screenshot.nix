{ pkgs ? import <nixpkgs> {} }:

let
  launcher = pkgs.writeShellScriptBin "niri-annotate-screenshot" ''
    set -u

    capture_dir="''${XDG_RUNTIME_DIR:-/tmp}"
    capture="$(${pkgs.coreutils}/bin/mktemp --tmpdir="$capture_dir" niri-annotate.XXXXXX.png)"
    ${pkgs.coreutils}/bin/rm -f "$capture"

    cleanup() {
      ${pkgs.coreutils}/bin/rm -f "$capture"
    }
    trap cleanup EXIT INT TERM

    if ! ${pkgs.niri}/bin/niri msg action screenshot \
      --show-pointer=false \
      --path "$capture"
    then
      exit 1
    fi

    # The screenshot action returns when the UI opens, so wait for Niri to
    # finish writing this invocation's unique file. Give cancelled captures
    # five minutes to disappear without leaving a permanent helper process.
    attempts=0
    while [ ! -s "$capture" ]; do
      if [ "$attempts" -ge 3000 ]; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
      attempts=$((attempts + 1))
    done

    ${pkgs.satty}/bin/satty \
      --filename "$capture" \
      --copy-command ${pkgs.wl-clipboard}/bin/wl-copy \
      --actions-on-enter=save-to-clipboard,exit \
      --actions-on-escape=exit \
      --early-exit
  '';
in
pkgs.symlinkJoin {
  name = "niri-annotate-screenshot";
  paths = [
    launcher
    pkgs.satty
  ];
}
