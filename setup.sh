#!/bin/bash

# Check if exactly one argument is passed (the Python version)
if [ $# -ne 1 ]; then
    # If not, print the usage information and exit with an error code
    echo "Usage: $0 <pythonVersion>"
    exit 1
fi

# Get the Python version from the first argument
pythonVersion=$1

# Remove any existing remote origin (if present) from the current Git repository
git remote remove origin

# Initialize a new Git repository in the current directory
git init

# Get the base name of the current directory (this will be the project/package name)
Name=$(basename "$(pwd)")
echo "Using repository name: $Name"

# Replace any hyphens in the name with underscores for the package name
packageName="${Name//-/_}"

# Create the folder structure src/${packageName}/ inside the project directory
mkdir -p "src/$packageName"

# Create the __init__.py file in the newly created package directory, 
# and define a simple 'hello' function that prints a message
cat > "src/$packageName/__init__.py" <<EOF
__version__ = "0.1.0"

EOF

# Create the pyproject.toml file, which includes the project metadata,
# Python version requirement, dependencies, and script definitions
cat > "pyproject.toml" <<EOF
[project]
name = "$Name"  # Set the project name (same as the directory name)
version = "0.1.0"  # Set the initial version of the package
description = "Add your description here"  # Placeholder for package description
readme = "README.md"  # The README file to include in the package
requires-python = ">=$pythonVersion"  # Python version requirement based on argument
dependencies = [
    "urllib3>=2.2.3",  # Default dependency (urllib3)
]

[project.scripts]
hello = "$packageName:hello"  # Define a script named 'hello' that calls the hello function

[build-system]
requires = ["hatchling"]  # Use hatchling as the build system
build-backend = "hatchling.build"  # Backend for building the package

[dependency-groups]
dev = [
    "ruff>=0.6.7",  # Development dependency for ruff (linter)
]
EOF

cat > "src/$packageName/__main__.py" <<EOF
def main():
    print("Hello World!")

if __name__ == "__main__":
    main()

EOF

# Run 'nix run' command to lock dependencies in nixpkgs (for reproducible builds)
nix run nixpkgs#uv lock

# Add the necessary files to Git: the Nix flake file, the lock file, README, pyproject.toml, 
# and the created Python package __init__.py
git add flake.nix uv.lock README.md pyproject.toml src/$packageName/__init__.py

# Output a success message with the project name and Python version
echo "Project setup complete for package '$packageName' with Python '$pythonVersion'."
