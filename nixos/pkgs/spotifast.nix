# Native Spotify client, repackaged from the upstream release tarball (same version as the Arch AUR package).
{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper
, alsa-lib, libpulseaudio, libglvnd, libxkbcommon, wayland, libx11, dbus }:

stdenv.mkDerivation rec {
  pname = "spotifast";
  version = "0.13.2";

  src = fetchurl {
    url = "https://github.com/crmne/spotifast/releases/download/v${version}/spotifast-v${version}-x86_64-unknown-linux-gnu.tar.gz";
    sha256 = "13692a5e1e758c70ef2f029591b5d22a8f51c82da4c4660a62295f9c35b9f93f";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ alsa-lib libpulseaudio dbus stdenv.cc.cc.lib ];
  # winit/glutin dlopen these at startup, so they cannot be found by autoPatchelf.
  runtimeLibs = lib.makeLibraryPath [ libglvnd libxkbcommon wayland libx11 ];

  installPhase = ''
    install -Dm755 spotifast $out/bin/spotifast
    wrapProgram $out/bin/spotifast --prefix LD_LIBRARY_PATH : "$runtimeLibs"
    install -Dm644 packaging/applications/spotifast.desktop $out/share/applications/spotifast.desktop
    install -Dm644 packaging/icons/spotifast.svg $out/share/icons/hicolor/scalable/apps/spotifast.svg
  '';

  meta = {
    description = "Native Spotify client";
    homepage = "https://github.com/crmne/spotifast";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "spotifast";
  };
}
