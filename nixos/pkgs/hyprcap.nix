{ lib, stdenvNoCC, fetchurl, makeWrapper
, bash, coreutils, findutils, gnugrep, gnused, gawk, procps, util-linux
, hyprland, grim, slurp, jq, wl-clipboard, hyprpicker, libnotify, wf-recorder, fuzzel
}:

stdenvNoCC.mkDerivation rec {
  pname = "hyprcap";
  version = "1.7.0";

  src = fetchurl {
    # Upstream v1.7.0, matching the working Arch capture workflow.
    url = "https://raw.githubusercontent.com/alonso-herreros/hyprcap/4de3086a47fb8dc25b03cd168b4d28683c336ddf/hyprcap";
    sha256 = "4fac5cf9253d49ac7530dec31b14fde82348978c8b95cf7c81bf173ab520985b";
  };
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/hyprcap"
    substituteInPlace "$out/bin/hyprcap" \
      --replace-fail 'readonly VERSION="DEV"' 'readonly VERSION="${version}"'
    patchShebangs "$out/bin/hyprcap"
    wrapProgram "$out/bin/hyprcap" --prefix PATH : ${lib.makeBinPath [
      bash coreutils findutils gnugrep gnused gawk procps util-linux
      hyprland grim slurp jq wl-clipboard hyprpicker libnotify wf-recorder fuzzel
    ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    timeout 10 "$out/bin/hyprcap" --version | grep -F '1.7.0'
    timeout 10 "$out/bin/hyprcap" --help > /dev/null
  '';

  meta = {
    description = "Screenshots and recordings with frozen region selection for Hyprland";
    homepage = "https://github.com/alonso-herreros/hyprcap";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "hyprcap";
  };
}
