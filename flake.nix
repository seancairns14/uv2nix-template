{
  description = "General-purpose Python project using uv2nix";

  ### --- Inputs (Dependencies) ---
  inputs = {
    # Official nixpkgs set (unstable channel)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # pyproject.nix handles builds from pyproject.toml
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # uv2nix extracts dependency graphs from uv lockfiles
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    # Optional: overlays and default package overrides
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.uv2nix.follows = "uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
    
  };

  ### --- Outputs (Main Build Logic) ---
  outputs = { self, nixpkgs, uv2nix, pyproject-nix, pyproject-build-systems, ... }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      # Automatically detect project name and normalized package name
      # Replace if needed 
      projectName = "comfy-scripting";
      packageName = "comfy_scripting";

      # Load project dependency graph and metadata using uv2nix
      workspace = uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ./.;
      };

      # Overlay for standard builds (non-editable)
      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel"; # use wheels over sdists if possible
      };

      # Overlay for development (editable source)
      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      # Define per-system Python dependency sets
      pythonSets = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Base build set for selected Python version
          baseSet = pkgs.callPackage pyproject-nix.build.packages {
            python = pkgs.python3;
          };

          # Override scope to include custom test derivations (mypy/pytest)
          pyprojectOverrides = final: prev: {
            ${projectName} = prev.${projectName}.overrideAttrs (old: {
              passthru = old.passthru // {
                tests = (old.tests or { }) // {
                  # mypy type checking
                  mypy = final.stdenv.mkDerivation {
                    name = "${final.${projectName}.name}-mypy";
                    inherit (final.${projectName}) src;
                    nativeBuildInputs = [
                      (final.mkVirtualEnv "${projectName}-typing-env" {
                        ${projectName} = [ "typing" ];
                      })
                    ];
                    dontConfigure = true;
                    dontInstall = true;
                    buildPhase = ''
                      mkdir $out
                      mypy --strict . --junit-xml $out/junit.xml
                    '';
                  };

                  # pytest + code coverage
                  pytest = final.stdenv.mkDerivation {
                    name = "${final.${projectName}.name}-pytest";
                    inherit (final.${projectName}) src;
                    nativeBuildInputs = [
                      (final.mkVirtualEnv "${projectName}-pytest-env" {
                        ${projectName} = [ "test" ];
                      })
                    ];
                    dontConfigure = true;
                    buildPhase = ''
                      runHook preBuild
                      pytest --cov tests --cov-report html tests
                      runHook postBuild
                    '';
                    installPhase = ''
                      mv htmlcov $out
                    '';
                  };
                };
              };
            });
          };

        in baseSet.overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            pyprojectOverrides
          ]
        )
      );

    in {
      ### --- Checks (Run CI tests) ---
      checks = forAllSystems (system:
        pythonSets.${system}.${projectName}.passthru.tests
      );

      ### --- Dev Shells ---
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          # Editable build (for use in dev shell)
          editablePythonSet = pythonSets.${system}.overrideScope (
            lib.composeManyExtensions [
              editableOverlay

              # Override with editable build
              (final: prev: {
                ${projectName} = prev.${projectName}.overrideAttrs (old: {
                  src = lib.fileset.toSource {
                    root = old.src;
                    fileset = lib.fileset.unions [
                      (old.src + "/pyproject.toml")
                      (old.src + "/README.md")
                      # Add source folder for lint/test coverage
                      (old.src + "/src/${packageName}/__init__.py")
                      (old.src + "/src/${packageName}/__main__.py")
                      
                      
                    ];
                  };
                  nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem { editables = [ ]; };
                });
              })
            ]
          );

          # Dev virtualenv with dev dependencies (linting, testing, etc.)
          venv = editablePythonSet.mkVirtualEnv "${projectName}-dev-env" {
            ${projectName} = [ "dev" ];
          };

        in {
          default = pkgs.mkShell {
            packages = [ venv pkgs.uv pkgs.vscode ];
            env = {
              UV_NO_SYNC = "1";
              UV_PYTHON = "${venv}/bin/python";
              UV_PYTHON_DOWNLOADS = "never";
            };
            shellHook = ''
              unset PYTHONPATH
              export REPO_ROOT=$(git rev-parse --show-toplevel)
            '';
          };
        }
      );

      ### --- NixOS Module (for optional service deployment) ---
      nixosModules = {
        ${projectName} = { config, lib, pkgs, ... }:
          let
            cfg = config.services.${projectName};
            inherit (pkgs) system;
            pythonSet = pythonSets.${system};
            inherit (lib.options) mkOption;
            inherit (lib.modules) mkIf;
          in {
            options.services.${projectName} = {
              enable = mkOption {
                type = lib.types.bool;
                default = false;
                description = "Enable ${projectName} systemd service";
              };

              exec-start = mkOption {
                type = lib.types.str;
                description = "Command to run the app (e.g., uvicorn main:app)";
              };

              venv = mkOption {
                type = lib.types.package;
                default = pythonSet.mkVirtualEnv "${projectName}-env" workspace.deps.default;
                description = "Virtual environment package to use";
              };
            };

            config = mkIf cfg.enable {
              systemd.services.${projectName} = {
                description = "Python web app";
                serviceConfig = {
                  ExecStart = cfg.exec-start;
                  Restart = "on-failure";
                  DynamicUser = true;
                  StateDirectory = "${projectName}";
                  RuntimeDirectory = "${projectName}";
                };
                wantedBy = [ "multi-user.target" ];
              };
            };
          };
      };

      ### --- Docker Image (optional container build) ---
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pythonSet = pythonSets.${system};
          venv = pythonSet.mkVirtualEnv "${projectName}-env" workspace.deps.default;
        in
        lib.optionalAttrs pkgs.stdenv.isLinux {
          docker = pkgs.dockerTools.buildLayeredImage {
            name = "${projectName}";
            tag = "latest";
            contents = [ pkgs.cacert ];
            config = {
              Cmd = [
                "${venv}/bin/python"
                "-m"
                "${packageName}"
              ];
            };
          };
        }
      );
    };
}
