{ pkgs ? import (fetchTarball https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz) {} }:
let
  poetry = pkgs.callPackage ../pkgs/poetry { python = pkgs.python3; inherit poetry2nix; };
  poetry2nix = import ./.. { inherit pkgs; inherit poetry; };

  pep425 = pkgs.callPackage ../pep425.nix {};
  pep425Python37 = pkgs.callPackage ../pep425.nix { python = pkgs.python37; };
  pep425OSX = pkgs.callPackage ../pep425.nix { isLinux = false; };

in
{
  trivial = pkgs.callPackage ./override-support { inherit poetry2nix; };
  override = pkgs.callPackage ./override-support { inherit poetry2nix; };
  top-packages-1 = pkgs.callPackage ./common-pkgs-1 { inherit poetry2nix; };
  top-packages-2 = pkgs.callPackage ./common-pkgs-2 { inherit poetry2nix; };
  pep425 = pkgs.callPackage ./pep425 { inherit pep425; inherit pep425OSX; inherit pep425Python37; };
  manylinux = pkgs.callPackage ./manylinux { inherit poetry2nix; };
}
