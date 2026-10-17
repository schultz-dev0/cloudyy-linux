{ lib, stdenv, fetchurl, zstd, autoPatchelfHook, qt6, coreutils
, libX11, libXrandr, libXinerama, libXi, libXScrnSaver, libsecret, glib, alsa-lib
, pipewire, libpulseaudio, tesseract, leptonica, curl, libarchive, systemdLibs
, libglvnd, zlib, openssl, gtk3, at-spi2-core, bzip2, cairo, fontconfig, gdk-pixbuf
, harfbuzz, pango
}:

# Closed-source binary from SignalRGB's Arch repo, built against Arch's system Qt.
# Bump: version + hash from https://pkgs.signalrgb.com/arch/beta/x86_64/signalrgb.db (%SHA256SUM%).
# Built from nixpkgs-unstable (flake.nix): needs glibc >= 2.43, GLIBCXX_3.4.36, Qt >= 6.11.
# ponytail: if a SignalRGB update outruns unstable's glibc/Qt, the fix is a newer unstable lock.
stdenv.mkDerivation rec {
  pname = "signalrgb";
  version = "2.5.82-7554";

  src = fetchurl {
    url = "https://pkgs.signalrgb.com/arch/beta/x86_64/signalrgb-${version}-x86_64.pkg.tar.zst";
    sha256 = "fb2f3fef7637f675d8ddb9a7403c9fc66565f834e40a235c133c906f7dc60668";
  };
  sourceRoot = ".";
  dontStrip = true;
  nativeBuildInputs = [ zstd autoPatchelfHook qt6.wrapQtAppsHook ];
  buildInputs = (with qt6; [
    qtbase qtdeclarative qt5compat qtcharts qthttpserver qtmultimedia qtnetworkauth
    qtpositioning qtserialport qtshadertools qtsvg qttools qtwebchannel qtwebengine
    qtwebsockets qtwebview
  ]) ++ [
    libX11 libXrandr libXinerama libXi libXScrnSaver libsecret glib alsa-lib pipewire
    libpulseaudio tesseract leptonica curl libarchive systemdLibs libglvnd zlib openssl
    gtk3 at-spi2-core bzip2 cairo fontconfig gdk-pixbuf harfbuzz pango
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r opt usr/share $out/
    install -Dm644 usr/lib/udev/rules.d/72-signalrgb.rules $out/lib/udev/rules.d/72-signalrgb.rules
    substituteInPlace $out/lib/udev/rules.d/72-signalrgb.rules \
      --replace-fail /bin/chmod ${coreutils}/bin/chmod
    # Upstream launcher cds into the install dir; plugins/effects are found relative to it.
    mkdir -p $out/bin
    ln -s $out/opt/signalrgb/SignalRgb $out/bin/signalrgb
    runHook postInstall
  '';

  qtWrapperArgs = [
    "--chdir" "${placeholder "out"}/opt/signalrgb"
    "--prefix" "QML_IMPORT_PATH" ":" "${placeholder "out"}/opt/signalrgb/qml"
  ];
  # wrapQtAppsHook only wraps bin/; wrap the real binary so the symlink gets the env too.
  postFixup = ''
    rm $out/bin/signalrgb
    makeQtWrapper $out/opt/signalrgb/SignalRgb $out/bin/signalrgb "''${qtWrapperArgs[@]}"
  '';
  dontWrapQtApps = true;

  meta = {
    description = "Control and sync your RGB with one app";
    homepage = "https://signalrgb.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "signalrgb";
  };
}
