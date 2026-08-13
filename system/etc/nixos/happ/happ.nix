{ pkgs ? import <nixpkgs> { }, forceXwayland ? false, forceSoftwareRendering ? false }:

let
  lib = pkgs.lib;

  qtPlatformArgs = lib.optionalString forceXwayland "--set QT_QPA_PLATFORM xcb";
  softwareRenderArgs = lib.optionalString forceSoftwareRendering
    "--set QML_SCENE_GRAPH software --set LIBGL_ALWAYS_SOFTWARE 1";

  runtimeDeps = with pkgs; [
    coreutils
    lsb-release
    net-tools
    iproute2
    iptables
    procps
  ];
in
pkgs.stdenv.mkDerivation rec {
  pname = "happ-desktop";
  version = "3.3.6";

  src = pkgs.fetchurl {
    url = "https://github.com/Happ-proxy/happ-desktop/releases/download/${version}/Happ.linux.x64.deb";
    sha256 = "p9rFEnc4e/4QSbGtQPQPLnSvIzpeqwILW+GmIu/8RqQ=";
  };

  nativeBuildInputs = with pkgs; [
    dpkg
    autoPatchelfHook
    makeWrapper
    qt6.wrapQtAppsHook
  ];

  # Happ ships a complete Qt runtime configured by its own qt.conf. Using the
  # nixpkgs Qt wrapper as well would mix two different plugin sets.
  dontWrapQtApps = true;

  buildInputs = with pkgs; [
    stdenv.cc.cc.lib
    libGL
    xorg.libX11
    xorg.libSM
    xorg.libICE
    xorg.libXext
    xorg.libXi
    xorg.libXtst
    e2fsprogs
    fontconfig
    freetype
    libgpg-error
    qt6.qtwayland
    openssl
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/happ $out/share/applications $out/bin
    dpkg -x $src .
    cp -r opt/happ/* $out/happ/

    if [ -d "usr/share" ]; then
      cp -r usr/share/* $out/share/
    fi

    ${lib.optionalString forceXwayland ''
      # The vendor Wayland plugins are unstable on wlroots compositors such as
      # niri, so use the bundled XCB backend through XWayland on this machine.
      rm -rf $out/happ/lib/plugins/wayland-*
      rm -f $out/happ/lib/plugins/platforms/libqwayland-*.so
    ''}

    for exe in Happ happd; do
      wrapProgram $out/happ/bin/$exe \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ pkgs.openssl ]}" \
        --prefix PATH : "${lib.makeBinPath runtimeDeps}" \
        --set SSL_CERT_FILE "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" \
        ${qtPlatformArgs} \
        ${softwareRenderArgs}
    done

    ln -s $out/happ/bin/Happ $out/bin/happ

    runHook postInstall
  '';

  meta = {
    description = "Happ proxy desktop client with a TUN daemon";
    homepage = "https://github.com/Happ-proxy/happ-desktop";
    platforms = [ "x86_64-linux" ];
    mainProgram = "happ";
  };
}
