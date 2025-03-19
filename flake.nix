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

    # extractNameAndPythonRequirements : File -> { name: String, requiresPython: String }
    extractNameAndPythonRequirements = file: let
      toml = loadTOML file;
    in {
      name = toml.package.name or "Unknown";  # You can adjust the default if needed
      requiresPython = toml.tool.poetry.dependencies.python or "Not specified";  # Default if not found
    };


    # Clean the TOML data
    cleanTOML = toml: lib.filterAttrs (n: v: v != null) {
      # Extract the `name` and `version` from the [project] section
      name = toml.project.name or null;
      version = toml.project.version or null;
      description = toml.project.description or null;
      readme = toml.project.readme or null;
      requiresPython = toml.project."requires-python" or null;
      dependencies = toml.project.dependencies or [];

      # Handle the [build-system] section (example, if you need it)
      buildSystemRequires = toml."build-system".requires or [];
      buildBackend = toml."build-system"."build-backend" or null;

      # Handle other sections as needed
      dependencyGroups = toml."dependency-groups".dev or [];

      # Optionally handle the [project.scripts] section if needed
      scripts = toml."project.scripts" or {};
    };


    # Load the TOML file and clean it
    tomlFile = loadTOML ./pyproject.toml;
    result = cleanTOML tomlFile;

    pythonVersion = if result.requiresPython != "" then
          "python" + (nixpkgs.lib.replaceStrings [ "." "=" "<" ">" ] [ "" "" "" "" ] result.requiresPython)
        else
          "python312";  # Default if not set in .env or environment

    Name = result.name;
    packageName = nixpkgs.lib.replaceStrings [" " "-"] ["_" "_"] Name;
    platform = "x86_64-linux";
    sourcePreference = "wheel";  # Change this to "sdist" if needed
    baseWorkspacePath = ./.;

    # Functions to load workspace and build overlays
    loadWorkspace = uv2nix.lib.workspace.loadWorkspace;
    createOverlay = workspace: workspace.mkPyprojectOverlay {
      sourcePreference = sourcePreference;
    };

    virtualEnvName = "${Name}-env";  # Derived from packageName
    editableEnvName = "${Name}-dev-env";  # Derived from packageName

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
        echo "Name: ${Name}"
        echo "Python Version: ${pythonVersion}"
        echo "Package Name: ${packageName}"
      '';
    };

    createEditableDevShell = let
      editableOverlay = (loadWorkspace 
      { workspaceRoot = ./.; }).mkEditablePyprojectOverlay {
          root = "REPO_ROOT";
        };

      editablePythonSet = pythonSet.overrideScope (
        lib.composeManyExtensions [
          editableOverlay
          (final: prev: {
            ${Name} = prev.${Name}.overrideAttrs (old: {
              src = lib.fileset.toSource {
                root = old.src;
                fileset = lib.fileset.unions [
                  (old.src + "/pyproject.toml")
                  (old.src + "/README.md")
                  (old.src + "/src/${packageName}/__init__.py")
                ];
              };
              nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem {
                editables = [ ];
              };
            });
          })
        ]
      );

      virtualenv = editablePythonSet.mkVirtualEnv virtualEnvName (loadWorkspace { workspaceRoot = ./.; }).deps.all;
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
    virtualEnvPackage = pythonSet.mkVirtualEnv virtualEnvName (loadWorkspace { workspaceRoot = ./.; }).deps.default;

  in
  {
    # Package the virtual environment as our main application
    packages.${platform}.default = virtualEnvPackage;

    # Make hello runnable with nix run
    apps.${platform} = {
      default = {
        type = "app";
        program = "${self.packages.${platform}.default}/bin/hello";
      };
    };

    # Define development shells
    devShells.${platform} = {
      impure = createImpureDevShell;
      uv2nix = createEditableDevShell;
    };
  };
}