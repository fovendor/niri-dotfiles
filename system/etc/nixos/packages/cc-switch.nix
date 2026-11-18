{ lib
, rustPlatform
, fetchFromGitHub
, fetchPnpmDeps
, pnpm_10
, pnpmConfigHook
, nodejs
, pkg-config
, wrapGAppsHook3
, gtk3
, webkitgtk_4_1
, libsoup_3
, libappindicator-gtk3
, glib-networking
, openssl
, makeDesktopItem
, copyDesktopItems
, desktop-file-utils
, symlinkJoin
, makeWrapper
}:

let
  base = rustPlatform.buildRustPackage (finalAttrs: {
  pname = "cc-switch";
  version = "4.0.12";

  src = fetchFromGitHub {
    owner = "farion1231";
    repo = "cc-switch";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Vvolng9/BB+uT/YMzu+P+3y2/yPjQb3nw5U6NTGjfhY=";
  };

  patches = [ ./cc-switch/preserve-managed-login.patch ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    fetcherVersion = 1;
    hash = "sha256-PWhOlIdqg1j2+kdUd7Ctv1olCJjIbChCnV5ak8J/KPA=";
  };

  cargoRoot = "src-tauri";
  buildAndTestSubdir = finalAttrs.cargoRoot;
  cargoHash = "sha256-PjgQbJgV/V/cOv2+IyzFhU19rnnMQfYd8aoiiDEWVAg=";
  buildFeatures = [ "tauri/custom-protocol" ];
  checkFeatures = [ "test-hooks" ];
  cargoTestFlags = [ "--lib" ];
  checkFlags = [ "managed_codex" "codex_login::tests" ];

  nativeBuildInputs = [ pnpm_10 pnpmConfigHook nodejs pkg-config wrapGAppsHook3 copyDesktopItems ];
  buildInputs = [ gtk3 webkitgtk_4_1 libsoup_3 libappindicator-gtk3 glib-networking openssl ];

  preBuild = ''
    pnpm run build:renderer
  '';

  desktopItems = [ (makeDesktopItem {
    name = "cc-switch";
    desktopName = "CC Switch";
    comment = "Switch AI coding providers and accounts";
    exec = "cc-switch %u";
    icon = "cc-switch";
    categories = [ "Development" ];
    mimeTypes = [ "x-scheme-handler/ccswitch" ];
    startupWMClass = "cc-switch";
  }) ];

  postInstall = ''
    install -Dm644 src-tauri/icons/128x128.png "$out/share/icons/hicolor/128x128/apps/cc-switch.png"
  '';

  preFixup = ''
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ desktop-file-utils ]})
  '';

  # A modest optimization level keeps local source rebuilds practical.
  CARGO_PROFILE_RELEASE_OPT_LEVEL = "1";
  CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
  CARGO_PROFILE_RELEASE_LTO = "false";

  meta = {
    description = "AI coding account switcher with preserved Codex desktop login";
    homepage = "https://github.com/farion1231/cc-switch";
    license = lib.licenses.mit;
    mainProgram = "cc-switch";
    platforms = lib.platforms.linux;
  };
});

in symlinkJoin {
  name = "cc-switch-${base.version}";
  inherit (base) pname version meta;
  paths = [ base ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram "$out/bin/cc-switch" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libappindicator-gtk3 ]}
  '';
  passthru = { inherit (base) cargoDeps pnpmDeps; };
}
