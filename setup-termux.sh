#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DOTFILES_REPO="termux-dotfiles"
KEY_PATH="$HOME/id_rsa.key"
SSH_DIR="$HOME/.ssh"
TARGET_KEY="$SSH_DIR/id_rsa"
CONFIG_FILE="$SSH_DIR/config"

# 1. Check if GitHub SSH access is already configured and working
SSH_OUTPUT=""
if command -v ssh >/dev/null 2>&1 && [[ -f "$TARGET_KEY" ]]; then
    SSH_OUTPUT=$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)
fi

if echo "$SSH_OUTPUT" | grep -q "^Hi "; then
    echo "GitHub SSH access is already configured. Skipping SSH key setup..."
else
    echo "Setting up GitHub SSH access..."

    # Verify id_rsa.key exists in Termux's home directory
    if [[ ! -f "$KEY_PATH" ]]; then
        echo "Error: Neither ~/.ssh/id_rsa nor $KEY_PATH was found."
        echo "Place id_rsa.key in your Termux home folder (~) before running this script."
        exit 1
    fi

    # Ensure openssh is installed before configuring keys
    if ! command -v ssh >/dev/null 2>&1; then
        pkg update -y && pkg install -y openssh
    fi

    # Create ~/.ssh, move the key, and set strict permissions
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    mv "$KEY_PATH" "$TARGET_KEY"
    chmod 600 "$TARGET_KEY"

    # Configure SSH for GitHub
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    if ! grep -q "Host github.com" "$CONFIG_FILE"; then
        cat << 'CONF' >> "$CONFIG_FILE"

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_rsa
  IdentitiesOnly yes
CONF
    fi

    # Add GitHub host key to known_hosts
    ssh-keyscan -t ed25519,rsa github.com >> "$SSH_DIR/known_hosts" 2>/dev/null
    chmod 644 "$SSH_DIR/known_hosts"

    # Authenticate via SSH key
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
fi

# 2. Extract GitHub username from SSH output
echo "$SSH_OUTPUT"
GITHUB_USER=$(echo "$SSH_OUTPUT" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')

if [[ -z "$GITHUB_USER" ]]; then
    echo "Error: Could not detect GitHub username from SSH output. Check your SSH key."
    exit 1
fi

echo "Detected GitHub user: $GITHUB_USER"

# 3. Update packages and install desktop, fuzzy search, k8s, and Neovim dependencies
echo "Updating packages and installing dependencies..."
pkg update -y && pkg upgrade -y
pkg install -y git openssh neovim starship chezmoi curl jq tmux termux-api ripgrep fd fzf kubectl

# 3b. Install kubie (via pkg if available, otherwise latest GitHub release binary)
if ! command -v kubie >/dev/null 2>&1; then
    echo "Installing kubie..."
    if ! pkg install -y kubie 2>/dev/null; then
        ARCH=$(uname -m)
        case "$ARCH" in
            aarch64|arm64) KUBIE_ARCH="arm64" ;;
            x86_64)        KUBIE_ARCH="amd64" ;;
            *)             KUBIE_ARCH="arm64" ;;
        esac
        KUBIE_URL=$(curl -fsSL "https://api.github.com/repos/sbstp/kubie/releases/latest" \
            | jq -r ".assets[] | select(.name | test(\"kubie-linux-${KUBIE_ARCH}$\")) | .browser_download_url")
        if [[ -n "$KUBIE_URL" ]]; then
            curl -fsSL "$KUBIE_URL" -o "$PREFIX/bin/kubie"
            chmod +x "$PREFIX/bin/kubie"
            echo "kubie installed to $PREFIX/bin/kubie"
        else
            echo "Warning: Could not find prebuilt kubie binary for $ARCH."
        fi
    fi
fi

# 4. Configure Git identity and push defaults automatically
echo "Configuring Git identity and defaults..."
USER_JSON=$(curl -fsSL "https://api.github.com/users/${GITHUB_USER}")
GIT_ID=$(echo "$USER_JSON" | jq -r '.id')
GIT_NAME=$(echo "$USER_JSON" | jq -r '.name // .login')
GIT_EMAIL="${GIT_ID}+${GITHUB_USER}@users.noreply.github.com"

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global push.autoSetupRemote true
git config --global pull.rebase false

echo "Git configured as: $GIT_NAME <$GIT_EMAIL>"

# 5. Create ~/projects/GitHub.com/<username>
PROJECTS_DIR="$HOME/projects/GitHub.com/$GITHUB_USER"
mkdir -p "$PROJECTS_DIR"

# 6. Initialize or update dotfiles via chezmoi over SSH
echo "Applying dotfiles from git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git..."
chezmoi init --apply "git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git"

# 7. Install LazyVim (VS Code-like Neovim setup) if not already installed
if [[ ! -f "$HOME/.config/nvim/lua/config/lazy.lua" ]]; then
    echo "Installing LazyVim starter configuration..."
    rm -rf "$HOME/.config/nvim"
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
fi

# 8. Clone all repositories into ~/projects/GitHub.com/<username>/
echo "Fetching repository list for $GITHUB_USER..."
cd "$PROJECTS_DIR"

REPOS=$(curl -fsSL "https://api.github.com/users/${GITHUB_USER}/repos?per_page=100" | jq -r '.[].ssh_url')

for REPO_URL in $REPOS; do
    REPO_NAME=$(basename "$REPO_URL" .git)
    if [[ ! -d "$PROJECTS_DIR/$REPO_NAME" ]]; then
        echo "Cloning $REPO_NAME..."
        git clone "$REPO_URL"
    else
        echo "Skipping $REPO_NAME (already exists)."
    fi
done

# 9. Ensure ~/.bashrc exists and initializes Starship + fzf
touch "$HOME/.bashrc"
if ! grep -q "starship init bash" "$HOME/.bashrc"; then
    cat << 'BASHRC' >> "$HOME/.bashrc"

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash)"
fi
BASHRC
fi

# 10. Apply Termux desktop properties immediately
termux-reload-settings || true

echo "Setup complete! All repositories are in $PROJECTS_DIR"
echo "Restart Termux or run 'source ~/.bashrc' to load Starship, fuzzy Ctrl+R, and kubie."#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DOTFILES_REPO="termux-dotfiles"
KEY_PATH="$HOME/id_rsa.key"
SSH_DIR="$HOME/.ssh"
TARGET_KEY="$SSH_DIR/id_rsa"
CONFIG_FILE="$SSH_DIR/config"

# 1. Check if GitHub SSH access is already configured and working
SSH_OUTPUT=""
if command -v ssh >/dev/null 2>&1 && [[ -f "$TARGET_KEY" ]]; then
    SSH_OUTPUT=$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)
fi

if echo "$SSH_OUTPUT" | grep -q "^Hi "; then
    echo "GitHub SSH access is already configured. Skipping SSH key setup..."
else
    echo "Setting up GitHub SSH access..."

    # Verify id_rsa.key exists in Termux's home directory
    if [[ ! -f "$KEY_PATH" ]]; then
        echo "Error: Neither ~/.ssh/id_rsa nor $KEY_PATH was found."
        echo "Place id_rsa.key in your Termux home folder (~) before running this script."
        exit 1
    fi

    # Ensure openssh is installed before configuring keys
    if ! command -v ssh >/dev/null 2>&1; then
        pkg update -y && pkg install -y openssh
    fi

    # Create ~/.ssh, move the key, and set strict permissions
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    mv "$KEY_PATH" "$TARGET_KEY"
    chmod 600 "$TARGET_KEY"

    # Configure SSH for GitHub
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    if ! grep -q "Host github.com" "$CONFIG_FILE"; then
        cat << 'CONF' >> "$CONFIG_FILE"

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_rsa
  IdentitiesOnly yes
CONF
    fi

    # Add GitHub host key to known_hosts
    ssh-keyscan -t ed25519,rsa github.com >> "$SSH_DIR/known_hosts" 2>/dev/null
    chmod 644 "$SSH_DIR/known_hosts"

    # Authenticate via SSH key
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
fi

# 2. Extract GitHub username from SSH output
echo "$SSH_OUTPUT"
GITHUB_USER=$(echo "$SSH_OUTPUT" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')

if [[ -z "$GITHUB_USER" ]]; then
    echo "Error: Could not detect GitHub username from SSH output. Check your SSH key."
    exit 1
fi

echo "Detected GitHub user: $GITHUB_USER"

# 3. Update packages and install desktop, fuzzy search, k8s, and Neovim dependencies
echo "Updating packages and installing dependencies..."
pkg update -y && pkg upgrade -y
pkg install -y git openssh neovim starship chezmoi curl jq tmux termux-api ripgrep fd fzf kubectl

# 3b. Install kubie (via pkg if available, otherwise latest GitHub release binary)
if ! command -v kubie >/dev/null 2>&1; then
    echo "Installing kubie..."
    if ! pkg install -y kubie 2>/dev/null; then
        ARCH=$(uname -m)
        case "$ARCH" in
            aarch64|arm64) KUBIE_ARCH="arm64" ;;
            x86_64)        KUBIE_ARCH="amd64" ;;
            *)             KUBIE_ARCH="arm64" ;;
        esac
        KUBIE_URL=$(curl -fsSL "https://api.github.com/repos/sbstp/kubie/releases/latest" \
            | jq -r ".assets[] | select(.name | test(\"kubie-linux-${KUBIE_ARCH}$\")) | .browser_download_url")
        if [[ -n "$KUBIE_URL" ]]; then
            curl -fsSL "$KUBIE_URL" -o "$PREFIX/bin/kubie"
            chmod +x "$PREFIX/bin/kubie"
            echo "kubie installed to $PREFIX/bin/kubie"
        else
            echo "Warning: Could not find prebuilt kubie binary for $ARCH."
        fi
    fi
fi

# 4. Configure Git identity and push defaults automatically
echo "Configuring Git identity and defaults..."
USER_JSON=$(curl -fsSL "https://api.github.com/users/${GITHUB_USER}")
GIT_ID=$(echo "$USER_JSON" | jq -r '.id')
GIT_NAME=$(echo "$USER_JSON" | jq -r '.name // .login')
GIT_EMAIL="${GIT_ID}+${GITHUB_USER}@users.noreply.github.com"

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global push.autoSetupRemote true
git config --global pull.rebase false

echo "Git configured as: $GIT_NAME <$GIT_EMAIL>"

# 5. Create ~/projects/GitHub.com/<username>
PROJECTS_DIR="$HOME/projects/GitHub.com/$GITHUB_USER"
mkdir -p "$PROJECTS_DIR"

# 6. Initialize or update dotfiles via chezmoi over SSH
echo "Applying dotfiles from git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git..."
chezmoi init --apply "git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git"

# 7. Install LazyVim (VS Code-like Neovim setup) if not already installed
if [[ ! -f "$HOME/.config/nvim/lua/config/lazy.lua" ]]; then
    echo "Installing LazyVim starter configuration..."
    rm -rf "$HOME/.config/nvim"
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
fi

# 8. Clone all repositories into ~/projects/GitHub.com/<username>/
echo "Fetching repository list for $GITHUB_USER..."
cd "$PROJECTS_DIR"

REPOS=$(curl -fsSL "https://api.github.com/users/${GITHUB_USER}/repos?per_page=100" | jq -r '.[].ssh_url')

for REPO_URL in $REPOS; do
    REPO_NAME=$(basename "$REPO_URL" .git)
    if [[ ! -d "$PROJECTS_DIR/$REPO_NAME" ]]; then
        echo "Cloning $REPO_NAME..."
        git clone "$REPO_URL"
    else
        echo "Skipping $REPO_NAME (already exists)."
    fi
done

# 9. Ensure ~/.bashrc exists and initializes Starship + fzf
touch "$HOME/.bashrc"
if ! grep -q "starship init bash" "$HOME/.bashrc"; then
    cat << 'BASHRC' >> "$HOME/.bashrc"

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash)"
fi
BASHRC
fi

# 10. Apply Termux desktop properties immediately
termux-reload-settings || true

echo "Setup complete! All repositories are in $PROJECTS_DIR"
echo "Restart Termux or run 'source ~/.bashrc' to load Starship, fuzzy Ctrl+R, and kubie."#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DOTFILES_REPO="termux-dotfiles"
KEY_PATH="$HOME/id_rsa.key"
SSH_DIR="$HOME/.ssh"
TARGET_KEY="$SSH_DIR/id_rsa"
CONFIG_FILE="$SSH_DIR/config"

# 1. Check if GitHub SSH access is already configured and working
SSH_OUTPUT=""
if command -v ssh >/dev/null 2>&1 && [[ -f "$TARGET_KEY" ]]; then
    SSH_OUTPUT=$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)
fi

if echo "$SSH_OUTPUT" | grep -q "^Hi "; then
    echo "GitHub SSH access is already configured. Skipping SSH key setup..."
else
    echo "Setting up GitHub SSH access..."

    # Verify id_rsa.key exists in Termux's home directory
    if [[ ! -f "$KEY_PATH" ]]; then
        echo "Error: Neither ~/.ssh/id_rsa nor $KEY_PATH was found."
        echo "Place id_rsa.key in your Termux home folder (~) before running this script."
        exit 1
    fi

    # Ensure openssh is installed before configuring keys
    if ! command -v ssh >/dev/null 2>&1; then
        pkg update -y && pkg install -y openssh
    fi

    # Create ~/.ssh, move the key, and set strict permissions
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    mv "$KEY_PATH" "$TARGET_KEY"
    chmod 600 "$TARGET_KEY"

    # Configure SSH for GitHub
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"

    if ! grep -q "Host github.com" "$CONFIG_FILE"; then
        cat << 'CONF' >> "$CONFIG_FILE"

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_rsa
  IdentitiesOnly yes
CONF
    fi

    # Add GitHub host key to known_hosts
    ssh-keyscan -t ed25519,rsa github.com >> "$SSH_DIR/known_hosts" 2>/dev/null
    chmod 644 "$SSH_DIR/known_hosts"

    # Authenticate via SSH key
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
fi

# 2. Extract GitHub username from SSH output
echo "$SSH_OUTPUT"
GITHUB_USER=$(echo "$SSH_OUTPUT" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')

if [[ -z "$GITHUB_USER" ]]; then
    echo "Error: Could not detect GitHub username from SSH output. Check your SSH key."
    exit 1
fi

echo "Detected GitHub user: $GITHUB_USER"

# 3. Update packages and install desktop, fuzzy search, k8s, and Neovim dependencies
echo "Updating packages and installing dependencies..."
pkg update -y && pkg upgrade -y
pkg install -y git openssh neovim starship chezmoi curl jq tmux termux-api ripgrep fd fzf kubectl

# 3b. Install kubie (via pkg if available, otherwise latest GitHub release binary)
if ! command -v kubie >/dev/null 2>&1; then
    echo "Installing kubie..."
    if ! pkg install -y kubie 2>/dev/null; then
        ARCH=$(uname -m)
        case "$ARCH" in
            aarch64|arm64) KUBIE_ARCH="arm64" ;;
            x86_64)        KUBIE_ARCH="amd64" ;;
            *)             KUBIE_ARCH="arm64" ;;
        esac
        KUBIE_URL=$(curl -fsSL "https://api.github.com/repos/sbstp/kubie/releases/latest" \
            | jq -r ".assets[] | select(.name | test(\"kubie-linux-${KUBIE_ARCH}$\")) | .browser_download_url")
        if [[ -n "$KUBIE_URL" ]]; then
            curl -fsSL "$KUBIE_URL" -o "$PREFIX/bin/kubie"
            chmod +x "$PREFIX/bin/kubie"
            echo "kubie installed to $PREFIX/bin/kubie"
        else
            echo "Warning: Could not find prebuilt kubie binary for $ARCH."
        fi
    fi
fi

# 4. Configure Git identity and push defaults automatically
echo "Configuring Git identity and defaults..."
USER_JSON=$(curl -fsSL "https://api.github.com/users/${GITHUB_USER}")
GIT_ID=$(echo "$USER_JSON" | jq -r '.id')
GIT_NAME=$(echo "$USER_JSON" | jq -r '.name // .login')
GIT_EMAIL="${GIT_ID}+${GITHUB_USER}@users.noreply.github.com"

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global push.autoSetupRemote true
git config --global pull.rebase false

echo "Git configured as: $GIT_NAME <$GIT_EMAIL>"

# 5. Create ~/projects/GitHub.com/<username>
PROJECTS_DIR="$HOME/projects/GitHub.com/$GITHUB_USER"
mkdir -p "$PROJECTS_DIR"

# 6. Initialize or update dotfiles via chezmoi over SSH
echo "Applying dotfiles from git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git..."
chezmoi init --apply "git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git"

# 7. Install LazyVim (VS Code-like Neovim setup) if not already installed
if [[ ! -f "$HOME/.config/nvim/lua/config/lazy.lua" ]]; then
    echo "Installing LazyVim starter configuration..."
    rm -rf "$HOME/.config/nvim"
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
fi

# 8. Clone all repositories into ~/projects/GitHub.com/<username>/
echo "Fetching repository list for $GITHUB_USER..."
cd "$PROJECTS_DIR"

REPOS=$(curl -fsSL "https://api.github.com/users/${GITHUB_USER}/repos?per_page=100" | jq -r '.[].ssh_url')

for REPO_URL in $REPOS; do
    REPO_NAME=$(basename "$REPO_URL" .git)
    if [[ ! -d "$PROJECTS_DIR/$REPO_NAME" ]]; then
        echo "Cloning $REPO_NAME..."
        git clone "$REPO_URL"
    else
        echo "Skipping $REPO_NAME (already exists)."
    fi
done

# 9. Ensure ~/.bashrc exists and initializes Starship + fzf
touch "$HOME/.bashrc"
if ! grep -q "starship init bash" "$HOME/.bashrc"; then
    cat << 'BASHRC' >> "$HOME/.bashrc"

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash)"
fi
BASHRC
fi

# 10. Apply Termux desktop properties immediately
termux-reload-settings || true

echo "Setup complete! All repositories are in $PROJECTS_DIR"
echo "Restart Termux or run 'source ~/.bashrc' to load Starship, fuzzy Ctrl+R, and kubie."
