# Builds a static `stack` executable from a stack source dir.
#
# Usage:
#
#     $(nix-build --no-link -A fullBuildScript --argstr src-dir /absolute/path/to/package/source)
{
  src-dir ? "/absolute/path/to/package/source",
  stack2nix-output-path ? "custom-stack2nix-output.nix",
  hackage-version ? "2021-07-12T00:00:00Z",
  package-name ? "name of the stack package",
  ghc-version ? "ghc8104", # Must be in nixpkgs and must match that determined by stack.yaml
  nixpkgs-revision ? "d00b5a5fa6fe8bdf7005abb06c46ae0245aec8b5",
}:
let
  cabalPackageName = package-name;
  compiler = ghc-version;

  pkgs = import (fetchTarball ("https://github.com/NixOS/nixpkgs/archive/" + nixpkgs-revision + ".tar.gz")) {};

  stack2nix-script = import ../static-stack2nix-builder/stack2nix-script.nix {
    inherit pkgs;
    inherit compiler;
    stack-project-dir = src-dir; # where stack.yaml is
    hackageSnapshot = hackage-version; # pins e.g. extra-deps without hashes or revisions
  };

  static-stack2nix-builder = import ../static-stack2nix-builder/default.nix {
    normalPkgs = pkgs;
    cabalPackageName = package-name;
    inherit compiler stack2nix-output-path;
    # disableOptimization = true; # for compile speed
  };

  static_package = with pkgs.haskell.lib;
    overrideCabal
      (appendConfigureFlags
        static-stack2nix-builder.static_package
        [
          # Official release flags:
          "-fsupported-build"
          "-fhide-dependency-versions"
          "-f-disable-git-info" # stack2nix turns that on, we turn it off again
        ]
      )
      (old: {
        # Enabling git info needs these extra deps.
        # TODO Make `stack2nix` accept per-package Cabal flags,
        #      so that `cabal2nix` would automatically add
        #      the right dependencies for us.
        executableHaskellDepends = (old.executableHaskellDepends or []) ++
          (with static-stack2nix-builder.haskell-static-nix_output.haskellPackages; [
            githash
            optparse-simple
          ]);
        # Put `git` on PATH, because `githash` calls it.
        preConfigure = ''
          export PATH=${pkgs.git}/bin:$PATH
          git --version
        '';
      });

  # Full invocation, including pinning `nix` version itself.
  fullBuildScript = pkgs.writeShellScript "stack2nix-and-build-script.sh" ''
    set -eu -o pipefail
    STACK2NIX_OUTPUT_PATH=$(${stack2nix-script})
    ${pkgs.nix}/bin/nix-build --no-link -A static_package \
      --argstr stack2nix-output-path "$STACK2NIX_OUTPUT_PATH" \
      --argstr package-name "${package-name}" \
      "$@"
  '';

in
  {
    inherit static_package;
    inherit fullBuildScript;
    # For debugging:
    inherit stack2nix-script;
    inherit static-stack2nix-builder;
  }
