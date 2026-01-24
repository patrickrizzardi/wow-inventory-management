# Version Management Guide

## Overview
This project uses semantic versioning (X.Y.Z) with strict increment rules and full git integration to ensure version consistency and automated releases.

**Important:** Releases must be created from the `main` branch.

## Current Version
Check the current version:
```bash
./publish.sh --version
# or
cat VERSION
```

## Creating a New Release

### Interactive Mode
Simply run:
```bash
./publish.sh
```

The script will:
1. **Check you're on the main branch** - Releases should come from main
2. **Check git status** - Ensures everything is committed and pushed
3. Show your current version
3. Suggest valid version increments
4. Ask you to enter a new version
5. Validate the version follows the rules
6. Update both `VERSION` and `InventoryManager.toc` files
7. **Commit the version changes**
8. **Push the commit to remote**
9. **Create and push a git tag** (e.g., `v1.0.1`)
10. **Create a GitHub release** (if GitHub CLI is installed)
11. Create a versioned zip file (e.g., `InventoryManager-1.0.1.zip`)

### Example Session
```
Current version: 1.0.0

Checking git status...
✓ Git status is clean and synced

Enter new version (or press Enter to cancel):
Valid increments from 1.0.0:
  - Patch: 1.0.1
  - Minor: 1.1.0
  - Major: 2.0.0

New version: 1.0.1

Version change: 1.0.0 -> 1.0.1
Continue? (y/N): y

Updating version files...
✓ Updated VERSION file to 1.0.1
✓ Updated InventoryManager.toc to version 1.0.1

Committing version changes...
✓ Committed version changes

Pushing commit to remote...
✓ Pushed commit to remote

Creating git tag...
✓ Created tag v1.0.1
✓ Pushed tag v1.0.1 to remote

✓ Package created: InventoryManager-1.0.1.zip

Creating GitHub release...
✓ Created GitHub release v1.0.1
✓ Uploaded InventoryManager-1.0.1.zip

✓ Version 1.0.1 released!

Summary:
  ✓ Version files updated and committed
  ✓ Changes pushed to remote
  ✓ Git tag v1.0.1 created
  ✓ Package InventoryManager-1.0.1.zip created
```

## Prerequisites

### Required
- Git repository with remote configured
- Must be on `main` branch (or you'll be warned)
- All changes committed and pushed before running

### Optional (for GitHub releases)
- GitHub CLI (`gh`) installed and authenticated
  - Install: https://cli.github.com/
  - Authenticate: `gh auth login`
  - Without `gh`, you can manually create releases on GitHub

## Git Status Requirements

Before creating a release, the script enforces:

### ✅ Must Pass
- **On main branch** - Releases should come from main (can override with confirmation)

- **No uncommitted changes** - All changes must be committed
  ```bash
  Error: You have uncommitted changes
  Please commit your changes first:
    git add .
    git commit -m "Your commit message"
  ```

- **All commits pushed** - Local branch must be synced with remote
  ```bash
  Error: Your branch is ahead of remote by N commit(s)
  Please push your changes first:
    git push
  ```

- **Up to date with remote** - No new commits on remote
  ```bash
  Error: Your branch is behind remote by N commit(s)
  Please pull changes first:
    git pull
  ```

### ⚠️ Warnings (can continue)
- **Not on main branch** - You can continue but it's recommended to release from main
- **Untracked files** - You can choose to continue or cancel
- **No upstream branch** - For new branches without remote tracking

## Version Rules

### ✅ Valid Increments
- **Patch**: Bug fixes, minor changes
  - `1.0.0` → `1.0.1` → `1.0.2` → ...
- **Minor**: New features, non-breaking changes
  - `1.0.0` → `1.1.0` → `1.2.0` → ...
- **Major**: Breaking changes
  - `1.0.0` → `2.0.0` → `3.0.0` → ...

### ❌ Invalid Operations
- **Cannot skip versions**: 
  - ❌ `1.0.0` → `1.0.5` (must go `1.0.0` → `1.0.1` → `1.0.2` → ...)
  - ❌ `1.0.0` → `1.5.0` (must go `1.0.0` → `1.1.0` → `1.2.0` → ...)
  
- **Cannot decrease versions**:
  - ❌ `1.5.0` → `1.0.0`
  - ❌ `2.0.0` → `1.9.9`

- **Can only increment by 1**:
  - ❌ `1.0.0` → `3.0.0` (must go through `2.0.0`)

## What Gets Created

### Git Objects
- **Commit**: `Bump version to X.Y.Z`
  - Updates `VERSION` file
  - Updates `InventoryManager.toc` file
- **Tag**: `vX.Y.Z` (e.g., `v1.0.1`)
  - Annotated tag with message "Release version X.Y.Z"
  - Pushed to remote automatically

### GitHub Release (if gh CLI available)
- **Title**: `Release X.Y.Z`
- **Tag**: `vX.Y.Z`
- **Assets**: `InventoryManager-X.Y.Z.zip` attached
- **Release notes**: Auto-generated with installation instructions

### Package
- **Zip file**: `InventoryManager-X.Y.Z.zip`
  - Ready for CurseForge upload
  - Contains only necessary addon files

## Troubleshooting

### Wrong Branch Error
```bash
# Switch to main branch
git checkout main

# Then run the script
./publish.sh
```

### Uncommitted Changes Error
```bash
# View what's uncommitted
git status

# Commit everything
git add .
git commit -m "Description of changes"

# Then run the script again
./publish.sh
```

### Unpushed Commits Error
```bash
# Push your commits
git push

# Then run the script again
./publish.sh
```

### Tag Already Exists
If a tag already exists (locally or remotely), you'll need to delete it first:
```bash
# Delete local tag
git tag -d v1.0.1

# Delete remote tag
git push origin --delete v1.0.1

# Then run the script again
./publish.sh
```

### GitHub CLI Not Installed
The script will still work without `gh` CLI - it will:
- Skip GitHub release creation
- Show manual instructions for creating the release
- Still create the git tag and zip package

To install GitHub CLI:
```bash
# See: https://cli.github.com/
# Then authenticate:
gh auth login
```

## Help
View help and examples:
```bash
./publish.sh --help
```

## Files Managed
- `VERSION` - Single source of truth for version number (tracked in git)
- `InventoryManager.toc` - Auto-updated with new version (tracked in git)
- `InventoryManager-X.Y.Z.zip` - Generated package with version in filename (not tracked)
- Git tags: `vX.Y.Z` - Automatically created and pushed

## Safety Features
- All changes are validated before being applied
- Automatic rollback if any step fails
- Git status must be clean before proceeding
- Version changes are committed automatically
- Tags are created and pushed automatically
- Confirmation required before applying changes
