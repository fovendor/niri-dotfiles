{ lib
, stdenv
, cmake
, ninja
, pkg-config
, git
, fetchFromGitHub
}:

let
  tomlplusplusSrc = fetchFromGitHub {
    owner = "marzer";
    repo = "tomlplusplus";
    rev = "v3.4.0";
    hash = "sha256-h5tbO0Rv2tZezY58yUbyRVpsfRjY3i+5TPkkxr6La8M=";
  };

  ftxuiSrc = fetchFromGitHub {
    owner = "ArthurSonzogni";
    repo = "FTXUI";
    rev = "v5.0.0";
    hash = "sha256-IF6G4wwQDksjK8nJxxAnxuCw2z2qvggCmRJ2rbg00+E=";
  };
in stdenv.mkDerivation {
  pname = "vader5d";
  version = "unstable-local";
  src = ../.;

  # Local repo may contain a previously generated ./build with absolute CMakeCache paths.
  # Nix copies src as-is, so we must drop stale build artifacts before configurePhase.
  postPatch = ''
    rm -rf build CMakeCache.txt CMakeFiles
  '';

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    git
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DENABLE_CLANG_TIDY=OFF"
    "-DFETCHCONTENT_SOURCE_DIR_TOMLPLUSPLUS=${tomlplusplusSrc}"
    "-DFETCHCONTENT_SOURCE_DIR_FTXUI=${ftxuiSrc}"
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 vader5d $out/bin/vader5d
    install -Dm755 vader5-debug $out/bin/vader5-debug
    runHook postInstall
  '';

  meta = with lib; {
    description = "Userspace daemon for Flydigi Vader 5 Pro";
    homepage = "https://github.com/BANANASJIM/flydigi-vader5";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
    mainProgram = "vader5d";
  };
}
