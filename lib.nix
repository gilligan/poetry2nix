{ lib }:
let
  inherit (import ./semver.nix { inherit lib; }) satisfiesSemver;

  # Check Python version is compatible with package
  isCompatible = pythonVersion: pythonVersions: let
    operators = {
      "||" = cond1: cond2: cond1 || cond2;
      "," = cond1: cond2: cond1 && cond2; # , means &&
    };
    tokens = builtins.filter (x: x != "") (builtins.split "(,|\\|\\|)" pythonVersions);
  in
    (
      builtins.foldl' (
        acc: v: let
          isOperator = builtins.typeOf v == "list";
          operator = if isOperator then (builtins.elemAt v 0) else acc.operator;
        in
          if isOperator then (acc // { inherit operator; }) else {
            inherit operator;
            state = operators."${operator}" acc.state (satisfiesSemver pythonVersion v);
          }
      )
        {
          operator = ",";
          state = true;
        }
        tokens
        ).state;

  readTOML = path: builtins.fromTOML (builtins.readFile path);

in {
  inherit isCompatible readTOML;
}
