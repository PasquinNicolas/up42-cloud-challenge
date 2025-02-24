#!/bin/bash

# Script: setup-repository.sh
# Description: Creates the directory structure for the UP42 cloud challenge project
# Usage: ./setup-repository.sh [target_directory]

set -euo pipefail

# Function to create directory and echo status
create_dir() {
    mkdir -p "$1"
    echo "Created directory: $1"
}

# Function to create file with initial content
create_file() {
    local file_path="$1"
    local content="$2"
    echo -e "$content" > "$file_path"
    echo "Created file: $file_path"
}

# Set target directory (use argument if provided, otherwise use current directory)
TARGET_DIR="${1:-up42-cloud-challenge}"

# Create main project directory
create_dir "$TARGET_DIR"
cd "$TARGET_DIR"

# Create directory structure
create_dir ".github/workflows"
create_dir "charts/up42-file-server/templates/minio"
create_dir "charts/up42-file-server/templates/s3www"
create_dir "charts/up42-file-server/files"
create_dir "terraform/environments/local"
create_dir "terraform/environments/production"
create_dir "terraform/modules"
create_dir "scripts/setup"
create_dir "docs/assets"
create_dir "docs/guides"

# Create initial Helm chart files
create_file "charts/up42-file-server/Chart.yaml" "apiVersion: v2
name: up42-file-server
description: A Helm chart for deploying MinIO and s3www services for UP42
version: 0.1.0
type: application"

create_file "charts/up42-file-server/values.yaml" "# Default values for up42-file-server
# This is a YAML-formatted file.

global:
  environment: local  # Can be 'local' or 'production'

# Add other default values here"

create_file "charts/up42-file-server/templates/_helpers.tpl" "{{/*
Expand the name of the chart.
*/}}
{{- define \"up42-file-server.name\" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix \"-\" }}
{{- end }}"

# Create .helmignore file
create_file "charts/up42-file-server/.helmignore" "# Patterns to ignore when building packages.
.DS_Store
# Common VCS dirs
.git/
.gitignore
.bzr/
.bzrignore
.hg/
.hgignore
.svn/
# Common backup files
*.swp
*.bak
*.tmp
*.orig
*~
# Various IDEs
.project
.idea/
*.tmproj
.vscode/"

# Create essential files with basic content
create_file "README.md" "# UP42 Cloud Engineering Challenge\n\nThis repository contains the solution for the UP42 Cloud Engineering challenge.\n\n## Overview\n\nTBD\n\n## Prerequisites\n\nTBD\n\n## Installation\n\nTBD\n\n## Usage\n\nTBD"

create_file "CHALLENGE.md" "# Challenge Implementation Thoughts\n\n## Design Decisions\n\nTBD\n\n## Concerns and Considerations\n\nTBD\n\n## Future Improvements\n\nTBD"

create_file ".gitignore" "# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl

# Helm
charts/*/charts
charts/*/Chart.lock

# IDE
.idea/
.vscode/

# OS
.DS_Store
Thumbs.db"

create_file "LICENSE" "Apache License, Version 2.0\nTBD - Full license text to be added"

echo "Repository structure has been created successfully in: $TARGET_DIR"
