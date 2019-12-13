{ autoPatchelfHook
, fetchFromPypi
, getManyLinuxDeps
, lib
, python
, isCompatible
, selectWheel
, buildPythonPackage
, pythonPackages
}:
{
  name,
  version,
  files,
  dependencies ? {},
  python-versions, # list
  ...
}: let

  supportedExtensions = lib.importJSON ./extensions.json;
  supportedRegex = ("^.*?(" + builtins.concatStringsSep "|" supportedExtensions + ")");

  isBdist = f: builtins.match "^.*?whl$" f.file != null;
  isSdist = f: ! isBdist f;

  matchesVersion = fname: builtins.match ("^.*" + builtins.replaceStrings [ "." ] [ "\\." ] version + ".*$") fname != null;
  hasSupportedExtension = fname: builtins.match supportedRegex fname != null;
  filteredFiles = builtins.filter (f: matchesVersion f.file && hasSupportedExtension f.file) files;

  binaryDist = selectWheel filteredFiles;
  sourceDist = builtins.filter isSdist filteredFiles;
  file = if (builtins.length sourceDist) > 0 then builtins.head sourceDist else builtins.head binaryDist;

  format =
    if isBdist file
    then "wheel"
    else "setuptools";

in
  buildPythonPackage {
    pname = name;
    version = version;

    doCheck = false; # We never get development deps
    dontStrip = true;

    inherit format;

    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs =  (getManyLinuxDeps file.file).pkg;
    NIX_PYTHON_MANYLINUX = (getManyLinuxDeps file.file).str;

    propagatedBuildInputs = let
    # Some dependencies like django gets the attribute name django
    # but dependencies try to access Django
    deps = builtins.map (d: lib.toLower d) (builtins.attrNames dependencies);
    in
    builtins.map (n: pythonPackages.${n}) deps;

    meta = {
      broken = ! isCompatible python.version python-versions;
      license = [];
    };

    src = fetchFromPypi {
      pname = lib.debug.traceVal(name);
      file = lib.debug.traceVal(file.file);
      inherit (file) hash;
    # We need to retrieve kind from the interpreter and the filename of the package
    # Interpreters should declare what wheel types they're compatible with (python type + ABI)
    # Here we can then choose a file based on that info.
    kind = if format == "setuptools" then "source" else (builtins.elemAt (lib.strings.splitString "-" file.file) 2);
  };
}


