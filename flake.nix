{
  description = "Hello world flake using uv2nix";

  # Inputs
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    toml2nix = {
      url = "github:erooke/toml2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # Outputs
  outputs = { self, nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, toml2nix, ... }:
  let
    inherit (nixpkgs) lib;


    loadTOML = file: builtins.fromTOML (builtins.readFile file);

    cleanTOML = toml: {
      name = toml.name or "hello-world";
      version = toml.version or "1.0.0";
      requires-python = toml.requires-python or "=3.12";
      dependencies = toml.dependencies or [];
    };


    # Load the TOML file and clean it
    tomlData = loadTOML ./pyproject.toml;
    cleanedData = cleanTOML tomlData;

    pythonVersionRaw = if cleanedData.requires-python != "" then
          "python" + (nixpkgs.lib.replaceStrings [ "." "=" "<" ">" ] [ "" "" "" "" ] cleanedData.requires-python)
        else
          "python312";  # Default if not set in .env or environment


    #packageName = cleanedData.name;
    packageName = "hello-world";

    pythonVersion = "python312";
    platform = "x86_64-linux";
    sourcePreference = "wheel";  # Change this to "sdist" if needed
    baseWorkspacePath = ./.;

    # Modularized paths and package names
    repoRoot = builtins.getEnv "REPO_ROOT";
    repoRootExists = builtins.pathExists repoRoot;


    # Functions to load workspace and build overlays
    loadWorkspace = uv2nix.lib.workspace.loadWorkspace;
    createOverlay = workspace: workspace.mkPyprojectOverlay {
      sourcePreference = sourcePreference;
    };

    virtualEnvName = "${packageName}-env";  # Derived from packageName
    editableEnvName = "${packageName}-dev-env";  # Derived from packageName

    # Overlay and fixups
    pyprojectOverrides = _final: _prev: {
      # Build fixups can be implemented here
    };

    # Define the platform-specific pkgs and Python version
    pkgs = nixpkgs.legacyPackages.${platform};
    python = pkgs.${pythonVersion};

    # Build the python package set
    buildPythonSet = pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    };

    pythonSet = buildPythonSet.overrideScope (
      lib.composeManyExtensions [
        pyproject-build-systems.overlays.default
        (createOverlay (loadWorkspace { workspaceRoot = baseWorkspacePath; }))
        pyprojectOverrides
      ]
    );

    # Functions to create dev shells
    createImpureDevShell = pkgs.mkShell rec {
      packages = [ python pkgs.uv ];
      env = {
        UV_PYTHON_DOWNLOADS = "never";
        UV_PYTHON = python.interpreter;
        LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;
      };
      shellHook = ''
        unset PYTHONPATH
        echo "Impure DevShell"
        echo "Repo root is: $REPO_ROOT"
        echo "Python Version: ${pythonVersionRaw}"
        echo "Package Name: ${packageName}"
      '';
    };

    createEditableDevShell = let
      editableOverlay = if repoRootExists then
        (loadWorkspace { workspaceRoot = baseWorkspacePath; }).mkEditablePyprojectOverlay {
          root = repoRoot;
        }
      else
        builtins.throw "REPO_ROOT directory does not exist: ${repoRoot}";  # Throw an error if it doesn't exist.

      editablePythonSet = pythonSet.overrideScope (
        lib.composeManyExtensions [
          editableOverlay
          (final: prev: {
            ${packageName} = prev.${packageName}.overrideAttrs (old: {
              src = lib.fileset.toSource {
                root = old.src;
                fileset = lib.fileset.unions [
                  (old.src + "/pyproject.toml")
                  (old.src + "/README.md")
                  (old.src + "/src/hello_world/__init__.py")
                ];
              };
              nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem {
                editables = [ ];
              };
            });
          })
        ]
      );

      virtualenv = editablePythonSet.mkVirtualEnv virtualEnvName (loadWorkspace { workspaceRoot = baseWorkspacePath; }).deps.all;
    in pkgs.mkShell {
      packages = [ virtualenv pkgs.uv ];
      env = {
        UV_NO_SYNC = "1";
        UV_PYTHON = "${virtualenv}/bin/python";
        UV_PYTHON_DOWNLOADS = "never";
      };
      shellHook = ''
        unset PYTHONPATH
        echo "Pure DevShell"
        echo "Repo root is: $REPO_ROOT"
        export REPO_ROOT=$(git rev-parse --show-toplevel)
        echo "test"
      '';
    };

    # Create virtual environment for app
    virtualEnvPackage = pythonSet.mkVirtualEnv virtualEnvName (loadWorkspace { workspaceRoot = baseWorkspacePath; }).deps.default;

  in
  {
    # Package the virtual environment as our main application
    packages.${platform}.default = virtualEnvPackage;

    # Make hello runnable with nix run
    apps.${platform} = {
      default = {
        type = "app";
        program = "${self.packages.${platform}.default}/bin/${packageName}";
      };
    };

    # Define development shells
    devShells.${platform} = {
      impure = createImpureDevShell;
      uv2nix = createEditableDevShell;
    };
  };
}