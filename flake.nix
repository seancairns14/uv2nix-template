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
  outputs = 
    { self, 
      nixpkgs, 
      uv2nix, 
      pyproject-nix, 
      pyproject-build-systems, 
      toml2nix, 
      ... 
    }:
    let
      inherit (nixpkgs) lib;  # Import Nixpkgs library to access common Nix functions
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      StartApp = "${packageName}:hello";
      settingsModules = {
        prod = "${packageName}.settings";
      };

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
          sourcePreference = "wheel";
        };

      editableOverlay = workspace.mkEditablePyprojectOverlay {
          root = "$REPO_ROOT";
        };
      
      loadTOML = file: builtins.fromTOML (builtins.readFile file);

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

      Name = result.name;  # Extract package name
      packageName = nixpkgs.lib.replaceStrings [" " "-"] ["_" "_"] Name;  # Format package name with dashes
      platform = "x86_64-linux";  # Define target platform
      sourcePreference = "wheel";  # Prefer wheel over sdist (source distribution)

      # Set names for virtual environments
      virtualEnvName = "${Name}-env";  # Standard virtualenv name based on package
      editableEnvName = "${Name}-dev-env";  # Editable dev environment name


      # Python sets grouped per system
      pythonSets = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) stdenv;

          # Base Python package set from pyproject.nix
          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = pkgs.python312;
          };

          # An overlay of build fixups
          pyprojectOverrides = final: prev: {

          
            ${Name} = prev.${Name}.overrideAttrs (old: {

              # Remove tests from passthru
              passthru = old.passthru // { };
            });

          };

        in
        baseSet.overrideScope (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.default
              overlay
              pyprojectOverrides
            ]
          )
        
      );

      # Static roots grouped per system
      staticRoots = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs) stdenv;

          pythonSet = pythonSets.${system};

          venv = pythonSet.mkVirtualEnv "${virtualEnvName}" workspace.deps.default;

        in
        stdenv.mkDerivation {
          name = "${Name}-static";
          inherit (pythonSet.${Name}) src;

          dontConfigure = true;
          dontBuild = true;

          nativeBuildInputs = [
            venv
          ];

          installPhase = ''
            mkdir -p $out
            cp -r ${venv} $out/
          '';
        }
      );

      in
      {
        checks = forAllSystems (
          system:
          let
            pythonSet = pythonSets.${system};
          in
          # Inherit tests from passthru.tests into flake checks
          pythonSet.${Name}.passthru.tests
        );

        nixosModules = {
          ${Name} =
            {
              config,
              lib,
              pkgs,
              ...
            }:

            let
              cfg = config.services.${Name};
              inherit (pkgs) system;

              pythonSet = pythonSets.${system};

              inherit (lib.options) mkOption;
              inherit (lib.modules) mkIf;
            in
            {
              options.services.${Name} = {
                enable = mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = ''
                    Enable "${Name}"
                  '';
                };

                settings-module = mkOption {
                  type = lib.types.string;
                  default = settingsModules.prod;
                  description = ''
                    "${Name}" settings module
                  '';
                };

                venv = mkOption {
                  type = lib.types.package;
                  default = pythonSet.mkVirtualEnv "${virtualEnvName}" workspace.deps.default;
                  description = ''
                   "${Name}" virtual environment package
                  '';
                };

                static-root = mkOption {
                  type = lib.types.package;
                  default = staticRoots.${system};
                  description = ''
                    "${Name}" static root
                  '';
                };
              };

              config = mkIf cfg.enable {
                systemd.services.${Name} = {
                  description = "'${Name}' server";

                  serviceConfig = {
                    ExecStart = ''
                      ${cfg.venv}/bin/python -m ${packageName}.hello
                    '';
                    Restart = "on-failure";

                    DynamicUser = true;
                    StateDirectory = "${Name}";
                    RuntimeDirectory = "${Name}";

                    BindReadOnlyPaths = [
                      "${
                        config.environment.etc."ssl/certs/ca-certificates.crt".source
                      }:/etc/ssl/certs/ca-certificates.crt"
                      builtins.storeDir
                      "-/etc/resolv.conf"
                      "-/etc/nsswitch.conf"
                      "-/etc/hosts"
                      "-/etc/localtime"
                    ];
                  };

                  wantedBy = [ "multi-user.target" ];
                };
              };

            };

        };

        packages = forAllSystems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
            pythonSet = pythonSets.${system};
          in
          lib.optionalAttrs pkgs.stdenv.isLinux {
            # Expose Docker container in packages
            docker =
              let
                venv = pythonSet.mkVirtualEnv "${virtualEnvName}" workspace.deps.default;
              in
              pkgs.dockerTools.buildLayeredImage {
                name = "${Name}";
                contents = [];
                config = {
                  Cmd = [
                    "sh" "-c" ''
                      source ${venv}/bin/activate
                      ${StartApp}
                      echo "Container: ${Name} Started"
                    ''
                  ];
                  Env = [
                  
                  ];
                };
              };
          }
        );

        # Use an editable Python set for development.
        devShells = forAllSystems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};

            editablePythonSet = pythonSets.${system}.overrideScope (
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
                    nativeBuildInputs =
                      old.nativeBuildInputs
                      ++ final.resolveBuildSystem {
                        editables = [ ];
                      };
                  });
                })
              ]
            );

            venv = editablePythonSet.mkVirtualEnv "${editableEnvName}" {
              ${Name} = [ "dev" ];
            };
          in
          {
            default = pkgs.mkShell {
              packages = [
                venv
                pkgs.uv
              ];
              env = {
                UV_NO_SYNC = "1";
                UV_PYTHON = "${venv}/bin/python";
                UV_PYTHON_DOWNLOADS = "never";
              };
              shellHook = ''
                unset PYTHONPATH
                export REPO_ROOT=$(git rev-parse --show-toplevel)
                echo "Dev Shell Started: ${editableEnvName}"
                echo "Python Version: ${pythonVersion}"
                echo "Package Name: ${packageName}"
                echo "REPO_ROOT: $REPO_ROOT"
              '';
            };
          }
        );
      };
}
   
   