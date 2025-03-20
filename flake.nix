{
  description = "Hello world flake using uv2nix";  # Description of the flake project

  # Inputs are the external dependencies or sources required by the flake
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";  # The Nixpkgs repository, using unstable version

    # pyproject-nix provides support for building Python packages
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";  # Reference to pyproject-nix repository
      inputs.nixpkgs.follows = "nixpkgs";  # Ensures it follows the nixpkgs input
    };

    # uv2nix provides integration with uv2nix for handling Python-based workspaces
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";  # Reference to uv2nix repository
      inputs.pyproject-nix.follows = "pyproject-nix";  # Ensures it follows pyproject-nix
      inputs.nixpkgs.follows = "nixpkgs";  # Ensures it follows nixpkgs
    };

    # pyproject-build-systems provides build-system packages for Python projects
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";  # Reference to pyproject-build-systems repository
      inputs.pyproject-nix.follows = "pyproject-nix";  # Ensures it follows pyproject-nix
      inputs.uv2nix.follows = "uv2nix";  # Ensures it follows uv2nix
      inputs.nixpkgs.follows = "nixpkgs";  # Ensures it follows nixpkgs
    };

    # toml2nix converts TOML files (like pyproject.toml) to Nix
    toml2nix = {
      url = "github:erooke/toml2nix";  # Reference to toml2nix repository
      inputs.nixpkgs.follows = "nixpkgs";  # Ensures it follows nixpkgs
    };
  };

  # Outputs define what the flake will provide (packages, apps, devShells, etc.)
  outputs = { self, nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, toml2nix, ... }:
  let
    inherit (nixpkgs) lib;  # Import Nixpkgs library to access common Nix functions

    # Load and parse TOML files using the fromTOML function
    loadTOML = file: builtins.fromTOML (builtins.readFile file);

    # Extract name and Python requirements from the pyproject.toml file
    extractNameAndPythonRequirements = file: let
      toml = loadTOML file;  # Load the TOML file
    in {
      name = toml.package.name or "Unknown";  # Extract package name or default to "Unknown"
      requiresPython = toml.tool.poetry.dependencies.python or "Not specified";  # Extract Python version or default to "Not specified"
    };

    # Clean the TOML data by removing null values and extracting useful attributes
    cleanTOML = toml: lib.filterAttrs (n: v: v != null) {
      name = toml.project.name or null;
      version = toml.project.version or null;
      description = toml.project.description or null;
      readme = toml.project.readme or null;
      requiresPython = toml.project."requires-python" or null;
      dependencies = toml.project.dependencies or [];
      buildSystemRequires = toml."build-system".requires or [];
      buildBackend = toml."build-system"."build-backend" or null;
      dependencyGroups = toml."dependency-groups".dev or [];
      scripts = toml."project.scripts" or {};
    };

    # Load and clean the pyproject.toml file
    tomlFile = loadTOML ./pyproject.toml;
    result = cleanTOML tomlFile;

    # Determine Python version to use
    pythonVersion = if result.requiresPython != "" then
          "python" + (nixpkgs.lib.replaceStrings [ "." "=" "<" ">" ] [ "" "" "" "" ] result.requiresPython)
        else
          "python312";  # Default to python 3.12 if not specified


    # Determine Dot Python version to use
    pythonDotVersion = if result.requiresPython != "" then
          "python" + (nixpkgs.lib.replaceStrings [ "=" "<" ">" ] [ "" "" "" ] result.requiresPython)
        else
          "python3.12";  # Default to python 3.12 if not specified

    Name = result.name;  # Extract package name
    packageName = nixpkgs.lib.replaceStrings [" " "-"] ["_" "_"] Name;  # Format package name with dashes
    platform = "x86_64-linux";  # Define target platform
    sourcePreference = "wheel";  # Prefer wheel over sdist (source distribution)
    baseWorkspacePath = ./.;  # Define base path for the workspace

    # Load the workspace using uv2nix
    loadWorkspace = uv2nix.lib.workspace.loadWorkspace;

    # Create overlay for the workspace
    createOverlay = workspace: workspace.mkPyprojectOverlay {
      sourcePreference = sourcePreference;
    };

    # Set names for virtual environments
    virtualEnvName = "${Name}-env";  # Standard virtualenv name based on package
    editableEnvName = "${Name}-dev-env";  # Editable dev environment name

    # Define overlays and Python package fixups
    pyprojectOverrides = _final: _prev: {
      # Define build fixups or customizations
    };

    # Select platform-specific Nixpkgs and Python version
    pkgs = nixpkgs.legacyPackages.${platform};
    python = pkgs.${pythonVersion};

    # Build the Python package set
    buildPythonSet = pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    };

    # Override the Python set with overlays
    pythonSet = buildPythonSet.overrideScope (
      lib.composeManyExtensions [
        pyproject-build-systems.overlays.default
        (createOverlay (loadWorkspace { workspaceRoot = baseWorkspacePath; }))
        pyprojectOverrides
      ]
    );

    # Functions to create development shells for impure and pure environments
    createImpureDevShell = pkgs.mkShell rec {
      packages = [ python pkgs.uv ];  # Include Python and uv (possibly uvloop or similar)
      env = {
        UV_PYTHON_DOWNLOADS = "never";  # Prevent Python downloads
        UV_PYTHON = python.interpreter;  # Set Python interpreter
        LD_LIBRARY_PATH = lib.makeLibraryPath pkgs.pythonManylinuxPackages.manylinux1;  # Set library path for compatibility
      };
      shellHook = ''
        unset PYTHONPATH  # Ensure PYTHONPATH is not set
        echo "Impure DevShell"  # Echo message for the user
        echo "Name: ${Name}"  # Echo the package name
        echo "Python Version: ${pythonDotVersion}"  # Echo the Python version
        echo "Package Name: ${packageName}"  # Echo the formatted package name
      '';
    };

    # Create editable dev shell for development environment
    createEditableDevShell = let
      editableOverlay = (loadWorkspace 
      { workspaceRoot = ./.; }).mkEditablePyprojectOverlay {
          root = "REPO_ROOT";
        };

      # Override Python set with editable overlay
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

      # Create virtual environment with editable set
      virtualenv = editablePythonSet.mkVirtualEnv virtualEnvName (loadWorkspace { workspaceRoot = ./.; }).deps.all;
    in pkgs.mkShell {
      packages = [ virtualenv pkgs.uv ];  # Include virtualenv and uv
      env = {
        UV_NO_SYNC = "1";  # Disable syncing for uv
        UV_PYTHON = "${virtualenv}/bin/python";  # Set the virtualenv Python interpreter
        UV_PYTHON_DOWNLOADS = "never";  # Prevent downloads
      };
      shellHook = ''
        unset PYTHONPATH  # Unset PYTHONPATH
        echo "Pure DevShell"  # Display a pure dev shell message
        export REPO_ROOT=$(git rev-parse --show-toplevel)  # Set the repo root using Git
        echo "Repo root is: $REPO_ROOT"  # Display the repo root
        echo "Name: ${Name}"  # Echo the package name
        echo "Python Version: ${pythonDotVersion}"  # Echo the Python version
        echo "Package Name: ${packageName}"  # Echo the formatted package name
      '';
    };

    # Create virtual environment for the application
    virtualEnvPackage = pythonSet.mkVirtualEnv virtualEnvName (loadWorkspace { workspaceRoot = ./.; }).deps.default;

  in
  {
    # Define the main package as the virtual environment
    packages.${platform}.default = virtualEnvPackage;

    # Make hello runnable with nix run (creates an executable for hello)
    apps.${platform} = {
      default = {
        type = "app";  # Defines the app type
        program = "${self.packages.${platform}.default}/bin/hello";  # Define the entry point of the app
      };
    };

    # Define the development shells (impure and pure)
    devShells.${platform} = {
      impure = createImpureDevShell;  # Define impure dev shell
      uv2nix = createEditableDevShell;  # Define editable dev shell
    };
  };
}
