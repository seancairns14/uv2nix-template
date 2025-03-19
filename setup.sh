#!/bin/bash

# Check if the correct number of arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <Name> <pythonVersion>"
    exit 1
fi

# Get the package name and python version from arguments
Name=$1
pythonVersion=$2

# Replace hyphens with underscores in the name
packageName="${Name//-/_}"

# Create the folder structure src/${packageName}/ inside the ${Name} directory
mkdir -p "$Name/src/$packageName"

cp ./flake.nix ./$Name/flake.nix

# Create the __init__.py file with the hello function
cat > "$Name/src/$packageName/__init__.py" <<EOF
def hello() -> None:
    print("Hello from hello-world!")
EOF

# Create the pyproject.toml file
cat > "$Name/pyproject.toml" <<EOF
[project]
name = "$Name"
version = "0.1.0"
description = "Add your description here"
readme = "README.md"
requires-python = "^$pythonVersion"
dependencies = [
    "urllib3>=2.2.3",
]

[project.scripts]
hello = "$packageName:hello"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[dependency-groups]
dev = [
    "ruff>=0.6.7",
]
EOF

echo "Project setup complete for package '$packageName' with Python '$pythonVersion'."
