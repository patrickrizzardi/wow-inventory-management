#!/bin/bash

# InventoryManager CurseForge Package Script with Version Management
# Creates a clean zip file ready for CurseForge upload

ADDON_NAME="InventoryManager"
VERSION_FILE="VERSION"
TOC_FILE="${ADDON_NAME}.toc"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display current version
show_version() {
    if [ -f "$VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$VERSION_FILE")
        echo -e "${BLUE}Current version: ${GREEN}${CURRENT_VERSION}${NC}"
    else
        echo -e "${RED}Error: VERSION file not found${NC}"
        exit 1
    fi
}

# Function to check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository${NC}"
        exit 1
    fi
}

# Function to check git status
check_git_status() {
    echo ""
    echo -e "${BLUE}Checking git status...${NC}"
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        echo -e "${RED}Error: You have uncommitted changes${NC}"
        echo ""
        echo -e "${YELLOW}Uncommitted changes:${NC}"
        git status --short
        echo ""
        echo -e "${YELLOW}Please commit your changes first:${NC}"
        echo "  git add ."
        echo "  git commit -m \"Your commit message\""
        return 1
    fi
    
    # Check for untracked files (excluding VERSION_GUIDE.md and zip files)
    local untracked=$(git ls-files --others --exclude-standard | grep -v "VERSION_GUIDE.md" | grep -v "\.zip$")
    if [ -n "$untracked" ]; then
        echo -e "${YELLOW}Warning: You have untracked files:${NC}"
        echo "$untracked"
        echo ""
        read -p "Continue anyway? (y/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi
    
    # Check if branch has upstream
    local branch=$(git rev-parse --abbrev-ref HEAD)
    if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then
        echo -e "${YELLOW}Warning: Current branch '${branch}' has no upstream${NC}"
        echo -e "${YELLOW}You may want to push your branch first${NC}"
        echo ""
        read -p "Continue anyway? (y/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            return 1
        fi
        return 0
    fi
    
    # Check if local is ahead of remote
    local ahead=$(git rev-list @{u}..HEAD --count 2>/dev/null)
    if [ "$ahead" -gt 0 ]; then
        echo -e "${RED}Error: Your branch is ahead of remote by ${ahead} commit(s)${NC}"
        echo ""
        echo -e "${YELLOW}Please push your changes first:${NC}"
        echo "  git push"
        return 1
    fi
    
    # Check if local is behind remote
    local behind=$(git rev-list HEAD..@{u} --count 2>/dev/null)
    if [ "$behind" -gt 0 ]; then
        echo -e "${RED}Error: Your branch is behind remote by ${behind} commit(s)${NC}"
        echo ""
        echo -e "${YELLOW}Please pull changes first:${NC}"
        echo "  git pull"
        return 1
    fi
    
    echo -e "${GREEN}✓ Git status is clean and synced${NC}"
    return 0
}

# Function to create and push git tag
create_git_tag() {
    local version=$1
    local tag="v${version}"
    
    echo ""
    echo -e "${BLUE}Creating git tag...${NC}"
    
    # Check if tag already exists locally
    if git rev-parse "$tag" >/dev/null 2>&1; then
        echo -e "${RED}Error: Tag ${tag} already exists locally${NC}"
        return 1
    fi
    
    # Check if tag exists on remote
    if git ls-remote --tags origin | grep -q "refs/tags/${tag}$"; then
        echo -e "${RED}Error: Tag ${tag} already exists on remote${NC}"
        return 1
    fi
    
    # Create annotated tag
    if git tag -a "$tag" -m "Release version ${version}"; then
        echo -e "${GREEN}✓ Created tag ${tag}${NC}"
    else
        echo -e "${RED}Error: Failed to create tag${NC}"
        return 1
    fi
    
    # Push tag to remote
    echo -e "${BLUE}Pushing tag to remote...${NC}"
    if git push origin "$tag"; then
        echo -e "${GREEN}✓ Pushed tag ${tag} to remote${NC}"
    else
        echo -e "${RED}Error: Failed to push tag${NC}"
        echo -e "${YELLOW}You can manually push with: git push origin ${tag}${NC}"
        return 1
    fi
    
    return 0
}

# Function to create GitHub release (requires gh CLI)
create_github_release() {
    local version=$1
    local tag="v${version}"
    local zip_file="${ADDON_NAME}-${version}.zip"
    
    # Check if gh CLI is available
    if ! command -v gh &> /dev/null; then
        echo ""
        echo -e "${YELLOW}Note: GitHub CLI (gh) not found. Skipping GitHub release creation.${NC}"
        echo -e "${YELLOW}Install gh CLI to auto-create releases: https://cli.github.com/${NC}"
        echo ""
        echo -e "${BLUE}Manual release instructions:${NC}"
        echo "  1. Go to: https://github.com/YOUR_USERNAME/${ADDON_NAME}/releases/new"
        echo "  2. Tag: ${tag}"
        echo "  3. Title: Release ${version}"
        echo "  4. Upload: ${zip_file}"
        return 0
    fi
    
    echo ""
    echo -e "${BLUE}Creating GitHub release...${NC}"
    
    # Check if already authenticated
    if ! gh auth status &> /dev/null; then
        echo -e "${YELLOW}GitHub CLI not authenticated. Please run: gh auth login${NC}"
        return 1
    fi
    
    # Create release with zip file
    if gh release create "$tag" "$zip_file" \
        --title "Release ${version}" \
        --notes "Release version ${version}

## Installation
Download \`${zip_file}\` and extract it to your WoW AddOns folder.

## Changes
See commit history for detailed changes." \
        --verify-tag; then
        echo -e "${GREEN}✓ Created GitHub release ${tag}${NC}"
        echo -e "${GREEN}✓ Uploaded ${zip_file}${NC}"
        
        # Get release URL
        local release_url=$(gh release view "$tag" --json url -q .url 2>/dev/null)
        if [ -n "$release_url" ]; then
            echo ""
            echo -e "${BLUE}Release URL: ${GREEN}${release_url}${NC}"
        fi
    else
        echo -e "${YELLOW}Note: Failed to create GitHub release${NC}"
        echo -e "${YELLOW}You can manually create it at: https://github.com/YOUR_USERNAME/${ADDON_NAME}/releases/new${NC}"
        return 1
    fi
    
    return 0
}

# Function to validate semantic version format
validate_version_format() {
    local version=$1
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid version format. Must be X.Y.Z (e.g., 1.0.0)${NC}"
        return 1
    fi
    return 0
}

# Function to parse version into array
parse_version() {
    local version=$1
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    echo "${VERSION_PARTS[@]}"
}

# Function to validate version increment
validate_increment() {
    local old_version=$1
    local new_version=$2
    
    # Parse versions
    local old_parts=($(parse_version "$old_version"))
    local new_parts=($(parse_version "$new_version"))
    
    local old_major=${old_parts[0]}
    local old_minor=${old_parts[1]}
    local old_patch=${old_parts[2]}
    
    local new_major=${new_parts[0]}
    local new_minor=${new_parts[1]}
    local new_patch=${new_parts[2]}
    
    # Check if version is going down
    if [ "$new_major" -lt "$old_major" ]; then
        echo -e "${RED}Error: Cannot decrease major version (${old_major} -> ${new_major})${NC}"
        return 1
    fi
    
    if [ "$new_major" -eq "$old_major" ] && [ "$new_minor" -lt "$old_minor" ]; then
        echo -e "${RED}Error: Cannot decrease minor version (${old_minor} -> ${new_minor})${NC}"
        return 1
    fi
    
    if [ "$new_major" -eq "$old_major" ] && [ "$new_minor" -eq "$old_minor" ] && [ "$new_patch" -lt "$old_patch" ]; then
        echo -e "${RED}Error: Cannot decrease patch version (${old_patch} -> ${new_patch})${NC}"
        return 1
    fi
    
    # Check if version is the same
    if [ "$new_major" -eq "$old_major" ] && [ "$new_minor" -eq "$old_minor" ] && [ "$new_patch" -eq "$old_patch" ]; then
        echo -e "${RED}Error: New version must be different from current version${NC}"
        return 1
    fi
    
    # Validate increment size (only +1 allowed)
    if [ "$new_major" -gt "$old_major" ]; then
        # Major version change
        if [ "$new_major" -ne $((old_major + 1)) ]; then
            echo -e "${RED}Error: Major version can only increment by 1 (${old_major} -> ${new_major})${NC}"
            return 1
        fi
        # When major changes, minor and patch should reset to 0
        if [ "$new_minor" -ne 0 ] || [ "$new_patch" -ne 0 ]; then
            echo -e "${YELLOW}Warning: When incrementing major version, minor and patch should be 0${NC}"
            echo -e "${YELLOW}Expected: $((old_major + 1)).0.0, got: ${new_version}${NC}"
        fi
    elif [ "$new_minor" -gt "$old_minor" ]; then
        # Minor version change
        if [ "$new_minor" -ne $((old_minor + 1)) ]; then
            echo -e "${RED}Error: Minor version can only increment by 1 (${old_minor} -> ${new_minor})${NC}"
            return 1
        fi
        # When minor changes, patch should reset to 0
        if [ "$new_patch" -ne 0 ]; then
            echo -e "${YELLOW}Warning: When incrementing minor version, patch should be 0${NC}"
            echo -e "${YELLOW}Expected: ${new_major}.$((old_minor + 1)).0, got: ${new_version}${NC}"
        fi
    else
        # Patch version change
        if [ "$new_patch" -ne $((old_patch + 1)) ]; then
            echo -e "${RED}Error: Patch version can only increment by 1 (${old_patch} -> ${new_patch})${NC}"
            return 1
        fi
    fi
    
    return 0
}

# Function to update TOC file with new version
update_toc_version() {
    local new_version=$1
    
    if [ ! -f "$TOC_FILE" ]; then
        echo -e "${RED}Error: TOC file not found: ${TOC_FILE}${NC}"
        return 1
    fi
    
    # Update the version line in TOC file
    sed -i "s/^## Version: .*/## Version: ${new_version}/" "$TOC_FILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Updated ${TOC_FILE} to version ${new_version}${NC}"
        return 0
    else
        echo -e "${RED}Error: Failed to update ${TOC_FILE}${NC}"
        return 1
    fi
}

# Function to create package
create_package() {
    local version=$1
    local output_file="${ADDON_NAME}-${version}.zip"
    
    # Check if zip is installed
    if ! command -v zip &> /dev/null; then
        echo -e "${RED}zip command not found. Attempting to install...${NC}"
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y zip unzip
        elif command -v yum &> /dev/null; then
            sudo yum install -y zip unzip
        else
            echo -e "${RED}Error: Could not install zip. Please install it manually:${NC}"
            echo "  sudo apt-get install zip unzip"
            exit 1
        fi
    fi
    
    # Remove old zip files
    rm -f ${ADDON_NAME}*.zip
    echo -e "${YELLOW}Removed old zip files${NC}"
    
    # Create zip with only necessary files
    zip -r "$output_file" . \
        -x "*.git*" \
        -x "*.sh" \
        -x "README.md" \
        -x "*.zip" \
        -x "*.code-workspace" \
        -x ".vscode/*" \
        -x ".idea/*" \
        -x "*.bak" \
        -x "*~" \
        -x "VERSION"
    
    echo ""
    echo -e "${GREEN}✓ Package created: ${output_file}${NC}"
    echo -e "${GREEN}✓ Ready to upload to CurseForge!${NC}"
    echo ""
    
    # Show what's included
    echo -e "${BLUE}Contents:${NC}"
    unzip -l "$output_file"
}

# Main script logic
case "${1:-}" in
    -v|--version)
        show_version
        exit 0
        ;;
    -h|--help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -v, --version    Show current version"
        echo "  -h, --help       Show this help message"
        echo "  (no options)     Create package with version bump"
        echo ""
        echo "Process:"
        echo "  1. Check git status (must be committed and pushed)"
        echo "  2. Prompt for new version"
        echo "  3. Update VERSION and .toc files"
        echo "  4. Commit version changes"
        echo "  5. Create and push git tag"
        echo "  6. Create GitHub release (if gh CLI available)"
        echo "  7. Create versioned zip package"
        echo ""
        echo "Version rules:"
        echo "  - Format: X.Y.Z (semantic versioning)"
        echo "  - Each segment can only increment by 1"
        echo "  - Cannot decrease version numbers"
        echo "  - Examples:"
        echo "    Valid:   1.0.0 -> 1.0.1, 1.0.1 -> 1.1.0, 1.1.0 -> 2.0.0"
        echo "    Invalid: 1.0.0 -> 1.0.5, 1.0.0 -> 1.5.0, 1.5.0 -> 1.0.0"
        exit 0
        ;;
esac

# Check if we're in a git repository
check_git_repo

# Show current version
show_version
CURRENT_VERSION=$(cat "$VERSION_FILE")

# Check git status before proceeding
if ! check_git_status; then
    exit 1
fi

echo ""
echo -e "${YELLOW}Enter new version (or press Enter to cancel):${NC}"
echo -e "${BLUE}Valid increments from ${CURRENT_VERSION}:${NC}"

# Parse current version to suggest options
PARTS=($(parse_version "$CURRENT_VERSION"))
MAJOR=${PARTS[0]}
MINOR=${PARTS[1]}
PATCH=${PARTS[2]}

echo -e "  - Patch: ${GREEN}${MAJOR}.${MINOR}.$((PATCH + 1))${NC}"
echo -e "  - Minor: ${GREEN}${MAJOR}.$((MINOR + 1)).0${NC}"
echo -e "  - Major: ${GREEN}$((MAJOR + 1)).0.0${NC}"
echo ""

read -p "New version: " NEW_VERSION

# Check if user cancelled
if [ -z "$NEW_VERSION" ]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

# Validate format
if ! validate_version_format "$NEW_VERSION"; then
    exit 1
fi

# Validate increment
if ! validate_increment "$CURRENT_VERSION" "$NEW_VERSION"; then
    exit 1
fi

# Confirm the change
echo ""
echo -e "${YELLOW}Version change: ${RED}${CURRENT_VERSION}${NC} -> ${GREEN}${NEW_VERSION}${NC}"
read -p "Continue? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled.${NC}"
    exit 0
fi

# Update VERSION file
echo ""
echo -e "${BLUE}Updating version files...${NC}"
echo "$NEW_VERSION" > "$VERSION_FILE"
echo -e "${GREEN}✓ Updated VERSION file to ${NEW_VERSION}${NC}"

# Update TOC file
if ! update_toc_version "$NEW_VERSION"; then
    # Rollback VERSION file
    echo "$CURRENT_VERSION" > "$VERSION_FILE"
    echo -e "${RED}Rolled back VERSION file${NC}"
    exit 1
fi

# Commit version changes
echo ""
echo -e "${BLUE}Committing version changes...${NC}"
if git add VERSION "$TOC_FILE" && git commit -m "Bump version to ${NEW_VERSION}"; then
    echo -e "${GREEN}✓ Committed version changes${NC}"
else
    echo -e "${RED}Error: Failed to commit version changes${NC}"
    # Rollback
    echo "$CURRENT_VERSION" > "$VERSION_FILE"
    update_toc_version "$CURRENT_VERSION"
    git reset HEAD VERSION "$TOC_FILE" 2>/dev/null
    exit 1
fi

# Push commit
echo -e "${BLUE}Pushing commit to remote...${NC}"
if git push; then
    echo -e "${GREEN}✓ Pushed commit to remote${NC}"
else
    echo -e "${RED}Error: Failed to push commit${NC}"
    echo -e "${YELLOW}You can manually push with: git push${NC}"
    echo -e "${YELLOW}Then run the script again or manually create the tag${NC}"
    exit 1
fi

# Create and push git tag
if ! create_git_tag "$NEW_VERSION"; then
    echo -e "${YELLOW}Warning: Tag creation failed, but version is committed${NC}"
    echo -e "${YELLOW}Continuing with package creation...${NC}"
fi

# Create package
echo ""
create_package "$NEW_VERSION"

# Create GitHub release
create_github_release "$NEW_VERSION"

echo ""
echo -e "${GREEN}✓ Version ${NEW_VERSION} released!${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo -e "  ${GREEN}✓${NC} Version files updated and committed"
echo -e "  ${GREEN}✓${NC} Changes pushed to remote"
echo -e "  ${GREEN}✓${NC} Git tag v${NEW_VERSION} created"
echo -e "  ${GREEN}✓${NC} Package ${ADDON_NAME}-${NEW_VERSION}.zip created"
