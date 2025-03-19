# uv2nix-template

A project template designed to streamline Python-based environments using nix and uv2nix. This template provides a consistent and isolated development environment, making it easier to set up Python projects on NixOS, and potentially on other systems as well.

Note: While this template is primarily intended for NixOS, it may also work on other systems, though compatibility has not been fully tested outside of NixOS.
Prerequisites

Before getting started, ensure that you have the following installed:

    Nix – A package manager and build system that will help set up the Python environment.
    Python – Any version of Python can be used. During setup, you’ll specify the desired version (e.g., 3.12.x or another version).

Getting Started

Follow these steps to quickly set up your project:
### 1. Clone the Repository

Clone this repository to your local machine with the following commands:
```bash
git clone https://github.com/seancairns14/uv2nix-template.git <project-name>
cd <project-name>
```
### 2. Run the Setup Script

Run the provided setup.sh script to initialize the project and configure the Python version. You can specify the Python version you prefer (e.g., 3.12, or any other version available).
```bash
bash setup.sh <python-version>
```
This script will:

    Initialize a Git repository (if not already initialized).
    Set up the environment using the specified Python version.

### 3. Enter the Development Shell

To enter the development environment, use the following command:
```bash
nix develop .#uv2nix --ignore-environment
```
This will load a pure development shell, ensuring your environment is isolated from the host system.
Optional: Impure Development Shell
Note: I use --ignore-environment this is Optional.

If you prefer to use a development shell that mirrors your host system (useful for testing or running commands that require your system's environment), you can use an impure development shell:
```bash
nix develop .#impure --ignore-environment
```
### 4. Build the Project

If you want to build the project for a specific target or generate a result without entering the shell, you can use:
```bash
nix build
```
This will execute the Nix build process and output the result as defined in the Nix expression.
### 5. Exit the Shell

Once you're done working in the shell, exit by typing:
```bash
exit
```
This will return you to your normal shell environment.
License

This project is licensed under the MIT License. See the LICENSE file for more details.
