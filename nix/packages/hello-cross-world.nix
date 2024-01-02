{
  lib,
  flake-self,
  cargoMeta,
  nix-filter,
  rustPlatform,
  pkg-config,
  openssl,
}:

rustPlatform.buildRustPackage {
  pname = cargoMeta.package.name;
  version = cargoMeta.package.version;

  src = nix-filter {
    root = ../../.;
    include = [
      "src"
      "Cargo.toml"
      "Cargo.lock"
    ];
  };

  cargoLock.lockFile = ../../Cargo.lock;

  VERGEN_IDEMPOTENT = "1";
  VERGEN_GIT_SHA = if flake-self ? "rev" then flake-self.rev else if flake-self ? "dirtyRev" then flake-self.dirtyRev else lib.warn "no git rev available" "NO_GIT_REPO";
  VERGEN_GIT_BRANCH = if flake-self ? "ref" then flake-self.ref else "";
  VERGEN_GIT_COMMIT_TIMESTAMP = flake-self.lastModifiedDate;

  # dependency example for stuff using openssl via pkgconfig
  nativeBuildInputs = [
    pkg-config
  ];
  buildInputs = [
    openssl
  ];
}
