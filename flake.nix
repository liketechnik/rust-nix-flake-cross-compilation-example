{
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };

  inputs.nixpkgs.url = "github:NixOs/nixpkgs/nixos-unstable";

  # not needed for cross-compilation;
  # allows to use rust versions not present in nixpkgs'
  # (see below)
  inputs.fenix = {
    url = "github:nix-community/fenix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # not needed for cross compilation;
  # this is kind of .gitignore but for `src = ./` in nix derivations
  inputs.nix-filter = {
    url = "github:numtide/nix-filter";
  };

  outputs = {
    self,
    nixpkgs,
    fenix,
    nix-filter,
    ...
  } @ inputs: let
    cargoMeta = builtins.fromTOML (builtins.readFile ./Cargo.toml);
    packageName = cargoMeta.package.name;

    forSystems = function:
      nixpkgs.lib.genAttrs [
        "x86_64-linux"
      ] (system: let
        pkgs = import nixpkgs {
          inherit system;

          overlays = [
            (final: prev: {
              ${packageName} = self.packages.${system}.${packageName};
            })
          ];
        };

        fenix-pkgs = fenix.packages.${system};
        # this allows to use the same toolchain for people using nix
        # and people not using nix (in settings where people that do not
        # have nix also work on the project)
        fenix-channel = fenix-pkgs.toolchainOf {
          channel = "nightly";
          date = builtins.replaceStrings ["nightly-"] [""] (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml)).toolchain.channel;
          sha256 = "sha256-SzEeSoO54GiBQ2kfANPhWrt0EDRxqEvhIbTt2uJt/TQ=";
        };
      in function { inherit system pkgs fenix-pkgs fenix-channel; });
  in {
    formatter = forSystems ({pkgs, ...}: pkgs.alejandra);

    packages = forSystems ({pkgs, fenix-pkgs, fenix-channel, system, ...}: {
      ${packageName} = pkgs.callPackage (./. + "/nix/packages/${packageName}.nix") {
        inherit cargoMeta;
        flake-self = self;
        nix-filter = import inputs.nix-filter;
        rustPlatform = pkgs.makeRustPlatform {
          cargo = fenix-channel.toolchain;
          rustc = fenix-channel.toolchain;
        };
      };
      default = self.packages.${system}.${packageName};
      "${packageName}-cross-aarch64" = let
        # replace with *.pkgsStatic to build statically linked binaries
        # replace the architecture in aarch64-multiplatform with any other
        # platform supported by nix to cross-compile for that platform...
        pkgsCross = pkgs.pkgsCross.aarch64-multiplatform.pkgs;
        # if building with nixpkgs' provided rust compiler,
        # this is not needed (see below)
        toolchain = with fenix-pkgs;
          combine [
            minimal.cargo
            minimal.rustc
            targets.${pkgsCross.rust.lib.toRustTarget pkgsCross.stdenv.targetPlatform}.latest.rust-std
          ];
      in
        pkgsCross.callPackage (./. + "/nix/packages/${packageName}.nix") {
          inherit cargoMeta;
          flake-self = self;
          nix-filter = import nix-filter;
          # remove `rustPlatform = ...` to build with nixpkgs' provided rust compiler
          # (i.e. fenix is not needed for cross-compilation to work)
          rustPlatform = pkgsCross.makeRustPlatform {
            cargo = toolchain;
            rustc = toolchain;
          };
        };
    });

    devShells = forSystems ({pkgs, fenix-pkgs, fenix-channel, ...}:
    let
        fenixRustToolchain = fenix-channel.withComponents [
          "cargo"
          "clippy-preview"
          "rust-src"
          "rustc"
          "rustfmt-preview"
        ];
    in {
      default = pkgs.callPackage (./. + "/nix/dev-shells/${packageName}.nix") {
        inherit fenixRustToolchain cargoMeta;
      };
      ci = pkgs.callPackage (./nix/dev-shells/ci.nix) {
        inherit fenixRustToolchain cargoMeta;
      };
    });
  };
}
