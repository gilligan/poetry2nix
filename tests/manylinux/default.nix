{ runCommand, lib, poetry2nix, python3 }:

let
  pkg = poetry2nix.mkPoetryPackage {
    python = python3;
    pyproject = ./pyproject.toml;
    poetryLock = ./poetry.lock;
    src = lib.cleanSource ./.;
  };
  p = pkg.python.withPackages (ps: [ ps.numpy ps.opencv-python ]);
in
  runCommand "test" {} ''
    ${p}/bin/python -c "import cv2"
    touch $out
  ''
