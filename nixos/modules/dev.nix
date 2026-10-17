# Development toolchains and Docker. ponytail: rustup/uv own their toolchains, so no pinned rustc/python here.
{ pkgs, ... }:
{
  virtualisation.docker.enable = true;
  users.users.schultz.extraGroups = [ "docker" ];

  environment.systemPackages = with pkgs; [
    rustup rust-analyzer
    nodejs_22 pnpm
    uv pipx
    jdk21 gradle
    gcc gnumake cmake meson ninja tree-sitter
    docker-compose
  ];
}
