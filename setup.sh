#!/bin/bash

# Check if the correct number of arguments are provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <pythonVersion>"
    exit 1
fi

# Get the package name and python version from arguments
pythonVersion=$1

git remote remove origin

git init

Name=$(basename "$(pwd)")
echo "Using repository name: $Name"

# Replace hyphens with underscores in the name
packageName="${Name//-/_}"

# Create the folder structure src/${packageName}/ inside the ${Name} directory
mkdir -p "src/$packageName"

# Create the __init__.py file with the hello function
cat > "src/$packageName/__init__.py" <<EOF
def hello() -> None:
    print("Hello from packageName!")
EOF

# Create the pyproject.toml file
cat > "pyproject.toml" <<EOF
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
