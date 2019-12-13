{ pkgs ? import <nixpkgs> {}
, lib ? pkgs.lib
, poetry ? null
, poetryLib ? import ./lib.nix { inherit lib; }
}:

let
  inherit (poetryLib) isCompatible readTOML;

  defaultPoetryOverrides = import ./overrides.nix { inherit pkgs; };

  mkEvalPep508 = import ./pep508.nix {
    inherit lib;
    stdenv = pkgs.stdenv;
  };

  getAttrDefault = attribute: set: default: (
    if builtins.hasAttr attribute set
    then builtins.getAttr attribute set
    else default
  );

  # Fetch the artifacts from the PyPI index. Since we get all
  # info we need from the lock file we don't use nixpkgs' fetchPyPi
  # as it modifies casing while not providing anything we don't already
  # have.
  #
  # Args:
  #   pname: package name
  #   file: filename including extension
  #   hash: SRI hash
  #   kind: Language implementation and version tag https://www.python.org/dev/peps/pep-0427/#file-name-convention
  fetchFromPypi = lib.makeOverridable (
    { pname, file, hash, kind }:
      pkgs.fetchurl {
        url = "https://files.pythonhosted.org/packages/${kind}/${lib.toLower (builtins.substring 0 1 file)}/${pname}/${file}";
        inherit hash;
      }
  );

  #
  # Returns the appropriate manylinux dependencies and string representation for the file specified
  #
  getManyLinuxDeps = f:
    let
      ml = pkgs.pythonManylinuxPackages;
    in
      if lib.strings.hasInfix "manylinux1" f then { pkg = [ ml.manylinux1 ]; str = "1"; }
      else if lib.strings.hasInfix "manylinux2010" f then { pkg = [ ml.manylinux2010 ]; str = "2010"; }
      else if lib.strings.hasInfix "manylinux2014" f then { pkg = [ ml.manylinux2014 ]; str = "2014"; }
      else { pkg = []; str = null; };

  mkPoetryPackage =
    { src
    , pyproject ? src + "/pyproject.toml"
    , poetrylock ? src + "/poetry.lock"
    , overrides ? defaultPoetryOverrides
    , meta ? {}
    , python ? pkgs.python3
    , ...
    }@attrs: let
      pyProject = readTOML pyproject;
      poetryLock = readTOML poetrylock;

      files = lib.getAttrFromPath ["metadata" "files"] poetryLock;

      specialAttrs = [ "pyproject" "poetrylock" "overrides" ];
      passedAttrs = builtins.removeAttrs attrs specialAttrs;

      evalPep508 = mkEvalPep508 python;

      poetryPkg = poetry.override { inherit python; };

      inherit (
        import ./pep425.nix {
          inherit lib python;
          inherit (pkgs) stdenv;
        }
      ) selectWheel;

      # Create an overriden version of pythonPackages
      #
      # We need to avoid mixing multiple versions of pythonPackages in the same
      # closure as python can only ever have one version of a dependency
      py = let
        packageOverrides = self: super: let
          getDep = depName: if builtins.hasAttr depName self then self."${depName}" else throw "foo";

          # Filter packages by their PEP508 markers
          partitions = let
            supportsPythonVersion = pkgMeta: if pkgMeta ? marker then (evalPep508 pkgMeta.marker) else true;
          in
            lib.partition supportsPythonVersion poetryLock.package;

          compatible = partitions.right;
          incompatible = partitions.wrong;

          lockPkgs = builtins.listToAttrs (builtins.map (
            pkgMeta: rec {
              name = pkgMeta.name;
              value = let
                drv = self.mkPoetryDep (pkgMeta // { files = files.${name}; });
                override = getAttrDefault pkgMeta.name overrides (_: _: drv: drv);
              in
                override self super drv;
            }
          ) compatible);

          # Null out any filtered packages, we don't want python.pkgs from nixpkgs
          nulledPkgs = builtins.listToAttrs (builtins.map (x: { name = x.name; value = null; }) incompatible);
        in
        {
          mkPoetryDep = self.callPackage ./mk-poetry-dep.nix {
            inherit fetchFromPypi getManyLinuxDeps lib python isCompatible selectWheel;
          };
        } // nulledPkgs // lockPkgs;
      in
        python.override { inherit packageOverrides; self = py; };
      pythonPackages = py.pkgs;

      getDeps = depAttr: let
        deps = getAttrDefault depAttr pyProject.tool.poetry {};
        depAttrs = builtins.map (d: lib.toLower d) (builtins.attrNames deps);
      in
        builtins.map (dep: pythonPackages."${dep}") depAttrs;

      getInputs = attr: getAttrDefault attr attrs [];
      mkInput = attr: extraInputs: getInputs attr ++ extraInputs;

      knownBuildSystems = {
        "intreehooks:loader" = [ py.pkgs.intreehooks ];
        "poetry.masonry.api" = [ poetryPkg ];
        "" = [];
      };

      getBuildSystemPkgs = let
        buildSystem = lib.getAttrFromPath [ "build-system" "build-backend" ] pyProject;
      in
        knownBuildSystems.${buildSystem} or (throw "unsupported build system ${buildSystem}");
    in
      pythonPackages.buildPythonApplication (
        passedAttrs // {
          pname = pyProject.tool.poetry.name;
          version = pyProject.tool.poetry.version;

          format = "pyproject";

          buildInputs = mkInput "buildInputs" getBuildSystemPkgs;
          propagatedBuildInputs = mkInput "propagatedBuildInputs" (getDeps "dependencies") ++ ([ pythonPackages.setuptools ]);
          checkInputs = mkInput "checkInputs" (getDeps "dev-dependencies");

          passthru = {
            inherit pythonPackages;
            python = py;
          };

          meta = meta // {
            inherit (pyProject.tool.poetry) description;
            licenses = [ pyProject.tool.poetry.license ];
          };

        }
      );

in
{
  inherit mkPoetryPackage defaultPoetryOverrides;
}
