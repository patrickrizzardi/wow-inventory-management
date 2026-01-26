#!/bin/bash

# InventoryManager Release Publisher
# Handles version bumping, git tagging, and package creation

ADDON_NAME="InventoryManager"
VERSION_FILE="VERSION"
TOC_FILE="${ADDON_NAME}.toc"
RELEASE_BRANCH="main"  # Change this if your default branch is different (e.g., "master")
CLAUDE_MODEL="${CLAUDE_MODEL:-claude-haiku-4-5-20251001}"  # Fast model for changelogs

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

# Function to check if on correct branch
check_branch() {
    local current_branch=$(git rev-parse --abbrev-ref HEAD)

    if [ "$current_branch" != "$RELEASE_BRANCH" ]; then
        echo -e "${RED}Error: Not on ${RELEASE_BRANCH} branch${NC}"
        echo -e "${YELLOW}Current branch: ${current_branch}${NC}"
        echo ""
        echo -e "${YELLOW}Releases should be created from the ${RELEASE_BRANCH} branch.${NC}"
        echo -e "${YELLOW}Switch to ${RELEASE_BRANCH} branch first:${NC}"
        echo "  git checkout ${RELEASE_BRANCH}"
        echo ""
        read -p "Continue anyway? (y/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    return 0
}

# Function to check git status
check_git_status() {
    echo ""
    echo -e "${BLUE}Checking git status...${NC}"

    # Check branch first
    if ! check_branch; then
        return 1
    fi

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

    # Check if tag exists on remote
    if git ls-remote --tags origin 2>/dev/null | grep -q "refs/tags/${tag}$"; then
        echo -e "${RED}Error: Tag ${tag} already exists on remote${NC}"
        echo -e "${YELLOW}Delete it first with: git push origin --delete ${tag}${NC}"
        return 1
    fi

    # Check if tag already exists locally - delete it to recreate at current HEAD
    if git rev-parse "$tag" >/dev/null 2>&1; then
        echo -e "${YELLOW}Tag ${tag} already exists locally, recreating at current HEAD...${NC}"
        git tag -d "$tag" >/dev/null 2>&1
    fi

    # Create annotated tag at current HEAD
    if git tag -a "$tag" -m "Release version ${version}"; then
        echo -e "${GREEN}✓ Created tag ${tag}${NC}"
    else
        echo -e "${RED}Error: Failed to create tag${NC}"
        return 1
    fi

    # Push tag to remote
    echo -e "${BLUE}Pushing tag to remote...${NC}"
    if git push origin "$tag" 2>&1; then
        echo -e "${GREEN}✓ Pushed tag ${tag} to remote${NC}"

        # GitHub can take 5-30 seconds to propagate tags
        echo -e "${BLUE}Waiting for GitHub to sync tag...${NC}"

        local max_seconds=30
        local elapsed=0
        local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local spinner_idx=0

        # Check immediately first (sometimes it's instant)
        if git ls-remote --tags origin 2>/dev/null | grep -q "refs/tags/${tag}$"; then
            echo -e "\r${GREEN}✓ Verified tag exists on GitHub (instant!)${NC}                    "
        else
            # Start spinner and keep checking
            while [ $elapsed -lt $max_seconds ]; do
                # Show spinner
                printf "\r${YELLOW}${spinner[$spinner_idx]}${NC} Checking GitHub... (${elapsed}s)"

                # Check if tag exists
                if git ls-remote --tags origin 2>/dev/null | grep -q "refs/tags/${tag}$"; then
                    echo -e "\r${GREEN}✓ Verified tag exists on GitHub (after ${elapsed}s)${NC}                    "
                    break
                fi

                # Update spinner and wait
                spinner_idx=$(( (spinner_idx + 1) % ${#spinner[@]} ))
                sleep 1
                elapsed=$((elapsed + 1))
            done

            # Final check if we timed out
            if [ $elapsed -ge $max_seconds ]; then
                echo -e "\r${RED}✗ Tag not found after ${max_seconds} seconds${NC}                              "
                echo -e "${YELLOW}GitHub may be experiencing delays. The tag might appear shortly.${NC}"
                echo -e "${YELLOW}Check: https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/tags${NC}"
                echo ""
                read -p "Continue anyway and try to create release? (y/N): " CONTINUE
                if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
                    return 1
                fi
            fi
        fi
    else
        echo -e "${RED}Error: Failed to push tag${NC}"
        echo -e "${YELLOW}You can manually push with: git push origin ${tag}${NC}"
        return 1
    fi

    return 0
}

# Function to show manual release instructions
show_manual_release_instructions() {
    local tag=$1
    local zip_file=$2

    # Get repo URL from git
    local repo_url=$(git remote get-url origin 2>/dev/null)
    local github_url="https://github.com/YOUR_USERNAME/${ADDON_NAME}"

    if [ -n "$repo_url" ]; then
        # Convert SSH/HTTPS to web URL
        github_url=$(echo "$repo_url" | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
    fi

    echo ""
    echo -e "${BLUE}Manual release instructions:${NC}"
    echo "  1. Go to: ${github_url}/releases/new"
    echo "  2. Tag: ${tag}"
    echo "  3. Title: Release ${tag#v}"
    echo "  4. Upload: ${zip_file}"
    echo ""
}

# Function to install GitHub CLI
install_github_cli() {
    echo ""
    echo -e "${BLUE}GitHub CLI Installation${NC}"
    echo ""

    # Detect OS and package manager
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        echo -e "${YELLOW}Detected Debian/Ubuntu system${NC}"
        echo ""
        echo "GitHub CLI will be installed using apt. This requires sudo."
        read -p "Install GitHub CLI now? (y/N): " INSTALL

        if [[ "$INSTALL" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BLUE}Installing GitHub CLI...${NC}"

            # Official installation method for Debian/Ubuntu
            if type -p curl >/dev/null 2>&1; then
                curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
                && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
                && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
                && sudo apt update \
                && sudo apt install gh -y
            else
                echo -e "${RED}Error: curl not found. Please install curl first:${NC}"
                echo "  sudo apt install curl"
                return 1
            fi

            if command -v gh &> /dev/null; then
                echo ""
                echo -e "${GREEN}✓ GitHub CLI installed successfully!${NC}"
                echo ""
                echo -e "${BLUE}Next step: Authenticate with GitHub${NC}"
                read -p "Run 'gh auth login' now? (y/N): " AUTH

                if [[ "$AUTH" =~ ^[Yy]$ ]]; then
                    gh auth login
                    return 0
                else
                    echo -e "${YELLOW}Run 'gh auth login' later to authenticate${NC}"
                    return 0
                fi
            else
                echo -e "${RED}Error: Installation failed${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}Skipped. Install manually later: https://cli.github.com/${NC}"
            return 1
        fi

    elif command -v yum &> /dev/null; then
        # RHEL/CentOS/Fedora
        echo -e "${YELLOW}Detected RHEL/CentOS/Fedora system${NC}"
        echo ""
        echo "GitHub CLI will be installed using yum/dnf. This requires sudo."
        read -p "Install GitHub CLI now? (y/N): " INSTALL

        if [[ "$INSTALL" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BLUE}Installing GitHub CLI...${NC}"
            sudo yum install -y 'dnf-command(config-manager)' \
            && sudo yum config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo \
            && sudo yum install -y gh

            if command -v gh &> /dev/null; then
                echo ""
                echo -e "${GREEN}✓ GitHub CLI installed successfully!${NC}"
                echo ""
                echo -e "${BLUE}Next step: Authenticate with GitHub${NC}"
                read -p "Run 'gh auth login' now? (y/N): " AUTH

                if [[ "$AUTH" =~ ^[Yy]$ ]]; then
                    gh auth login
                    return 0
                else
                    echo -e "${YELLOW}Run 'gh auth login' later to authenticate${NC}"
                    return 0
                fi
            else
                echo -e "${RED}Error: Installation failed${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}Skipped. Install manually later: https://cli.github.com/${NC}"
            return 1
        fi

    elif command -v brew &> /dev/null; then
        # macOS with Homebrew
        echo -e "${YELLOW}Detected Homebrew (macOS)${NC}"
        echo ""
        echo "GitHub CLI will be installed using Homebrew."
        read -p "Install GitHub CLI now? (y/N): " INSTALL

        if [[ "$INSTALL" =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BLUE}Installing GitHub CLI...${NC}"
            brew install gh

            if command -v gh &> /dev/null; then
                echo ""
                echo -e "${GREEN}✓ GitHub CLI installed successfully!${NC}"
                echo ""
                echo -e "${BLUE}Next step: Authenticate with GitHub${NC}"
                read -p "Run 'gh auth login' now? (y/N): " AUTH

                if [[ "$AUTH" =~ ^[Yy]$ ]]; then
                    gh auth login
                    return 0
                else
                    echo -e "${YELLOW}Run 'gh auth login' later to authenticate${NC}"
                    return 0
                fi
            else
                echo -e "${RED}Error: Installation failed${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}Skipped. Install manually later: https://cli.github.com/${NC}"
            return 1
        fi

    else
        # Unknown system
        echo -e "${YELLOW}Could not detect package manager${NC}"
        echo ""
        echo -e "${BLUE}Please install GitHub CLI manually:${NC}"
        echo "  https://cli.github.com/manual/installation"
        echo ""
        echo "Or use one of these methods:"
        echo "  - Debian/Ubuntu: See https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
        echo "  - RHEL/CentOS/Fedora: See https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
        echo "  - macOS: brew install gh"
        echo "  - Other: Download from https://github.com/cli/cli/releases"
        return 1
    fi
}

# Function to generate AI changelog using Claude
generate_ai_changelog() {
    local version=$1
    local previous_tag=$2

    # Check if Claude API key is available
    if [ -z "$CLAUDE_API_KEY" ]; then
        echo ""
        return 1
    fi

    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        return 1
    fi

    echo -e "${BLUE}Generating AI changelog...${NC}" >&2

    # Get commit history since last tag
    local commits
    if [ -n "$previous_tag" ]; then
        commits=$(git log "${previous_tag}..HEAD" --pretty=format:"%h - %s (%an)" 2>/dev/null)
    else
        # No previous tag - get all commits
        commits=$(git log --pretty=format:"%h - %s (%an)" 2>/dev/null)
    fi

    if [ -z "$commits" ]; then
        echo -e "${YELLOW}No commits found for changelog${NC}" >&2
        return 1
    fi

    # Get git diff stats
    local diff_stats
    if [ -n "$previous_tag" ]; then
        diff_stats=$(git diff "${previous_tag}..HEAD" --stat 2>/dev/null)
    else
        diff_stats=$(git diff --stat 2>/dev/null)
    fi

    # Create prompt for Claude
    local system_msg="You are a changelog generator for a World of Warcraft addon. Create a concise, user-friendly changelog.

CRITICAL: You are generating a changelog for the ADDON, not the development tools.
- IGNORE commits about build scripts, release tools, CI/CD, versioning systems
- IGNORE commits with: publish.sh, compress.sh, VERSION file, .gitignore, .github workflows
- FOCUS ONLY on changes to the actual addon functionality (Lua files, TOC file)
- If ALL commits are tooling/meta changes, return: NO_USER_CHANGES

Format:
## What's New in ${version}

### ✨ New Features
- Feature descriptions (if any)

### 🐛 Bug Fixes
- Bug fix descriptions (if any)

### ⚙️ Improvements
- Improvement descriptions (if any)

### 📝 Technical Changes
- Technical/refactor details (if any, keep brief)

Guidelines:
- Write for addon USERS, not developers
- Focus on user-visible changes IN THE ADDON
- Be concise but clear
- Group similar changes
- Omit version bump commits and build tool changes
- Use bullet points
- If no addon changes in a category, omit that section
- If ONLY tooling changes, return: NO_USER_CHANGES"

    local prompt="Commits since ${previous_tag:-initial release}:
${commits}

Diff stats:
${diff_stats}

Generate a user-friendly changelog for version ${version}."

    # Create JSON payload
    local temp_json=$(mktemp) || return 1

    jq -n \
        --arg model "$CLAUDE_MODEL" \
        --arg system "$system_msg" \
        --arg prompt "$prompt" \
        '{
            "model": $model,
            "max_tokens": 2000,
            "system": $system,
            "messages": [{"role": "user", "content": $prompt}]
        }' > "$temp_json"

    # Call Claude API
    local response
    response=$(curl -s -X POST \
        -H "x-api-key: $CLAUDE_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        -d @"$temp_json" \
        "https://api.anthropic.com/v1/messages")

    rm "$temp_json"

    # Extract changelog from response
    local changelog=$(echo "$response" | jq -r '.content[] | select(.type == "text") | .text' 2>/dev/null)

    if [ -z "$changelog" ]; then
        echo -e "${YELLOW}AI changelog generation failed${NC}" >&2
        return 1
    fi

    # Check if AI detected no user-facing changes
    if echo "$changelog" | grep -q "NO_USER_CHANGES"; then
        echo -e "${YELLOW}No user-facing addon changes detected${NC}" >&2
        return 1
    fi

    echo -e "${GREEN}✓ AI changelog generated${NC}" >&2
    echo "$changelog"
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
        echo -e "${YELLOW}GitHub CLI (gh) not found${NC}"
        echo ""
        read -p "Would you like to install GitHub CLI now? (y/N): " INSTALL_GH

        if [[ "$INSTALL_GH" =~ ^[Yy]$ ]]; then
            if install_github_cli; then
                # Try to create release after installation
                if command -v gh &> /dev/null; then
                    echo ""
                    echo -e "${BLUE}Attempting to create GitHub release...${NC}"
                    # Continue with release creation below
                else
                    echo -e "${YELLOW}GitHub CLI not available. Skipping release creation.${NC}"
                    show_manual_release_instructions "$tag" "$zip_file"
                    return 0
                fi
            else
                show_manual_release_instructions "$tag" "$zip_file"
                return 0
            fi
        else
            show_manual_release_instructions "$tag" "$zip_file"
            return 0
        fi
    fi

    echo ""
    echo -e "${BLUE}Creating GitHub release...${NC}"

    # Check if GITHUB_TOKEN or GH_TOKEN is available
    # gh commands work directly with these env vars without needing gh auth login
    if [ -n "$GITHUB_TOKEN" ] || [ -n "$GH_TOKEN" ]; then
        echo -e "${BLUE}Using GITHUB_TOKEN from environment${NC}"
        # No need to run gh auth login - gh commands work with the env token directly
    elif ! gh auth status &> /dev/null; then
        # No token in env and not authenticated
        echo -e "${YELLOW}GitHub CLI not authenticated and no GITHUB_TOKEN found${NC}"
        echo ""
        read -p "Run 'gh auth login' now? (y/N): " DO_LOGIN
        if [[ "$DO_LOGIN" =~ ^[Yy]$ ]]; then
            gh auth login
        else
            echo -e "${YELLOW}Attempting release anyway...${NC}"
        fi
    fi

    # Generate AI changelog if Claude API key is available
    # Get PREVIOUS tag (not current one) - exclude the tag we just created
    local current_tag="v${version}"
    local previous_tag=$(git tag --sort=-version:refname | grep -v "^${current_tag}$" | head -1)

    local ai_changelog=$(generate_ai_changelog "$version" "$previous_tag")
    local changelog_status=$?

    # Build release notes
    local release_notes
    if [ $changelog_status -eq 0 ] && [ -n "$ai_changelog" ]; then
        # AI changelog succeeded
        release_notes="$ai_changelog

## 📦 Installation

**Option 1: CurseForge (Recommended)**
Install via [CurseForge](https://www.curseforge.com/wow/addons/inventorymanager) for automatic updates

**Option 2: Manual**
Download \`${zip_file}\` and extract it to your WoW AddOns folder

## 🔗 Links
- [CurseForge Page](https://www.curseforge.com/wow/addons/inventorymanager)
- [Issues](https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/issues)
- [Changelog](https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/releases)"
    else
        # Fallback to basic release notes
        if [ -z "$CLAUDE_API_KEY" ]; then
            echo -e "${YELLOW}⚠ No AI changelog generated (CLAUDE_API_KEY not set)${NC}"
            echo -e "${BLUE}Tip: Set CLAUDE_API_KEY for automatic AI-generated changelogs${NC}"
        elif [ $changelog_status -eq 1 ]; then
            echo -e "${YELLOW}⚠ No user-facing addon changes detected (using basic notes)${NC}"
            echo -e "${BLUE}Note: Only tooling/build script changes since last release${NC}"
        else
            echo -e "${YELLOW}⚠ AI changelog generation failed (using basic notes)${NC}"
        fi

        release_notes="Release version ${version}

## 📦 Installation

**Option 1: CurseForge (Recommended)**
Install via [CurseForge](https://www.curseforge.com/wow/addons/inventorymanager) for automatic updates

**Option 2: Manual**
Download \`${zip_file}\` and extract it to your WoW AddOns folder

## 📝 Changes
See commit history for detailed changes.

## 🔗 Links
- [CurseForge Page](https://www.curseforge.com/wow/addons/inventorymanager)
- [Issues](https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')/issues)"
    fi

    # Create release with zip file
    local create_output
    create_output=$(gh release create "$tag" "$zip_file" \
        --title "Release ${version}" \
        --notes "$release_notes" 2>&1)
    local create_status=$?

    if [ $create_status -eq 0 ]; then
        echo -e "${GREEN}✓ Created GitHub release ${tag}${NC}"
        echo -e "${GREEN}✓ Uploaded ${zip_file}${NC}"

        # Get release URL
        local release_url=$(gh release view "$tag" --json url -q .url 2>/dev/null)
        if [ -n "$release_url" ]; then
            echo ""
            echo -e "${BLUE}Release URL: ${GREEN}${release_url}${NC}"
        else
            # Fallback: construct URL from git remote
            local repo_url=$(git remote get-url origin 2>/dev/null)
            if [ -n "$repo_url" ]; then
                # Convert SSH URL to HTTPS
                repo_url=$(echo "$repo_url" | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
                echo ""
                echo -e "${BLUE}Release URL: ${GREEN}${repo_url}/releases/tag/${tag}${NC}"
            fi
        fi
    else
        # Command failed, but let's check if release actually exists
        echo -e "${YELLOW}Release command returned error, checking if release exists...${NC}"

        if gh release view "$tag" &>/dev/null; then
            echo -e "${GREEN}✓ Release ${tag} exists on GitHub!${NC}"
            echo -e "${YELLOW}Note: Command reported error but release was created successfully${NC}"

            # Get release URL
            local repo_url=$(git remote get-url origin 2>/dev/null)
            if [ -n "$repo_url" ]; then
                repo_url=$(echo "$repo_url" | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
                echo ""
                echo -e "${BLUE}Release URL: ${GREEN}${repo_url}/releases/tag/${tag}${NC}"
            fi
        else
            echo -e "${RED}✗ Failed to create GitHub release${NC}"
            echo ""
            echo -e "${YELLOW}Error output:${NC}"
            echo "$create_output"
            echo ""
            echo -e "${YELLOW}Possible issues:${NC}"
            echo "  - GITHUB_TOKEN may be expired or invalid"
            echo "  - Token needs 'repo' scope for releases"
            echo "  - Token may not have access to this repository"
            echo ""
            echo -e "${BLUE}Check your token at: https://github.com/settings/tokens${NC}"
            show_manual_release_instructions "$tag" "$zip_file"
            return 1
        fi
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

    # Get the addon directory name and parent path
    local addon_dir=$(basename "$(pwd)")
    local parent_dir=$(dirname "$(pwd)")

    # Create zip from parent directory so the addon folder is the root
    # This ensures extracting creates: InventoryManager/contents
    # instead of just dumping files loose
    (cd "$parent_dir" && zip -r "${addon_dir}/${output_file}" "$addon_dir" \
        -x "${addon_dir}/.git/*" \
        -x "${addon_dir}/.git*" \
        -x "${addon_dir}/*.sh" \
        -x "${addon_dir}/README.md" \
        -x "${addon_dir}/*.zip" \
        -x "${addon_dir}/*.code-workspace" \
        -x "${addon_dir}/.vscode/*" \
        -x "${addon_dir}/.idea/*" \
        -x "${addon_dir}/.claude/*" \
        -x "${addon_dir}/*.bak" \
        -x "${addon_dir}/*~" \
        -x "${addon_dir}/VERSION")

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
        echo "  1. Check you're on ${RELEASE_BRANCH} branch"
        echo "  2. Check git status (must be committed and pushed)"
        echo "  3. Prompt for new version"
        echo "  4. Update VERSION and .toc files"
        echo "  5. Commit version changes"
        echo "  6. Create and push git tag"
        echo "  7. Create GitHub release (if gh CLI available)"
        echo "  8. Create versioned zip package"
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
