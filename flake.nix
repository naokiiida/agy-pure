{
  description = "Blazingly fast statusline, window title, and notification hooks for agy in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "agy-pure";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [ pkgs.zig.hook ];

          dontConfigure = true;
          dontInstall = true;

          buildPhase = ''
            runHook preBuild
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)
            zig build -Doptimize=ReleaseFast --prefix "$out"
            runHook postBuild
          '';

          meta = with pkgs.lib; {
            description = "Statusline, window title, and notification hooks for Antigravity CLI (agy)";
            homepage = "https://github.com/naokiiida/agy-pure";
            license = licenses.mit;
            platforms = platforms.all;
            maintainers = [ ];
          };
        };
      }
    );
}
