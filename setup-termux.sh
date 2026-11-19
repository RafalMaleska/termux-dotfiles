#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DOTFILES_REPO="termux-dotfiles"
KEY_PATH="$HOME/id_rsa.key"
SSH_DIR="$HOME/.ssh"
TARGET_KEY="$SSH_DIR/id_rsa"
CONFIG_FILE="$SSH_DIR/config"

# 1. Check if GitHub SSH access is already configured in native Termux
SSH_OUTPUT=""
if command -v ssh >/dev/null 2>&1 && [[ -f "$TARGET_KEY" ]]; then
    SSH_OUTPUT=$(ssh -o BatchMode=yes -T git@github.com 2>&1 || true)
fi

if echo "$SSH_OUTPUT" | grep -q "^Hi "; then
    echo "GitHub SSH access is already configured. Skipping SSH key setup..."
else
    echo "Setting up GitHub SSH access..."

    if [[ ! -f "$KEY_PATH" ]]; then
        echo "Error: Neither ~/.ssh/id_rsa nor $KEY_PATH was found."
        echo "Place id_rsa.key in your Termux home folder (~) before running this script."
        exit 1
    fi

    if ! command -v ssh >/dev/null 2>&1; then
        pkg update -y && pkg install -y openssh
    fi

    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"

    mv "$KEY_PATH" "$TARGET_KEY"
    chmod 600 "$TARGET_KEY"

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

    ssh-keyscan -t ed25519,rsa github.com >> "$SSH_DIR/known_hosts" 2>/dev/null
    chmod 644 "$SSH_DIR/known_hosts"

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

# 3. Install minimal native Termux packages + proot-distro Debian
echo "Updating native Termux and installing proot-distro..."
pkg update -y && pkg upgrade -y
pkg install -y openssh proot-distro termux-api curl jq

if [[ ! -d "$PREFIX/var/lib/proot-distro/installed-rootfs/debian" ]]; then
    echo "Installing Debian via proot-distro..."
    proot-distro install debian
else
    echo "Debian rootfs already installed. Skipping install..."
fi

# 4. Run full Linux environment setup inside Debian (apt, chezmoi, LazyVim, mise, repos)
echo "Configuring Debian environment inside proot-distro..."
proot-distro login debian --shared-tmp -- env GITHUB_USER="$GITHUB_USER" DOTFILES_REPO="$DOTFILES_REPO" TERMUX_HOME="$HOME" bash -euo pipefail << 'DEBIAN_SETUP'

# 4a. Install base Linux tools
apt-get update && apt-get upgrade -y
apt-get install -y git curl jq fzf ripgrep fd-find tmux neovim openssh-client ca-certificates unzip xz-utils build-essential

# 4b. Copy SSH keys & config from Termux home into Debian home
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
cp -f "$TERMUX_HOME/.ssh/id_rsa" "$HOME/.ssh/id_rsa"
cp -f "$TERMUX_HOME/.ssh/config" "$HOME/.ssh/config"
cp -f "$TERMUX_HOME/.ssh/known_hosts" "$HOME/.ssh/known_hosts"
chmod 600 "$HOME/.ssh/id_rsa" "$HOME/.ssh/config"
chmod 644 "$HOME/.ssh/known_hosts"

# 4c. Configure Git identity automatically
USER_JSON=$(curl -fsSL "https://api.github.com/users/${GITHUB_USER}")
GIT_ID=$(echo "$USER_JSON" | jq -r '.id')
GIT_NAME=$(echo "$USER_JSON" | jq -r '.name // .login')
GIT_EMAIL="${GIT_ID}+${GITHUB_USER}@users.noreply.github.com"

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global push.autoSetupRemote true
git config --global pull.rebase false

# 4d. Install Starship, chezmoi, and mise
if ! command -v starship >/dev/null 2>&1; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

if ! command -v chezmoi >/dev/null 2>&1; then
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
fi

if ! command -v mise >/dev/null 2>&1; then
    curl https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$PATH"

# 4e. Apply dotfiles via chezmoi over SSH
echo "Applying dotfiles from git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git..."
chezmoi init --apply "git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git"

# 4f. Install all DevOps & Kubernetes tools declared in ~/.config/mise/config.toml
echo "Installing DevOps tools via mise (linux-arm64)..."
mise install

# 4g. Install LazyVim if not already installed
if [[ ! -f "$HOME/.config/nvim/lua/config/lazy.lua" ]]; then
    echo "Installing LazyVim starter configuration..."
    rm -rf "$HOME/.config/nvim"
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
fi

# 4h. Clone all GitHub repositories into ~/projects/GitHub.com/<username>/
PROJECTS_DIR="$HOME/projects/GitHub.com/$GITHUB_USER"
mkdir -p "$PROJECTS_DIR"
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

# 4i. Ensure Debian ~/.bashrc activates Starship, fzf, and mise
touch "$HOME/.bashrc"
if ! grep -q "mise activate bash" "$HOME/.bashrc"; then
    cat << 'BASHRC' >> "$HOME/.bashrc"

export PATH="$HOME/.local/bin:$PATH"
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash)"
fi
BASHRC
fi

DEBIAN_SETUP

# 5. Apply Termux desktop properties (shortcuts & extra-keys) in native Termux
mkdir -p "$HOME/.termux"
cat << 'PROPS' > "$HOME/.termux/termux.properties"
shortcut.create-session = ctrl + t
shortcut.next-session = ctrl + tab
shortcut.previous-session = ctrl + shift + tab
shortcut.rename-session = ctrl + n
extra-keys = [['ESC','TAB','CTRL','ALT','-','/','UP','DOWN','LEFT','RIGHT']]
PROPS
termux-reload-settings || true

# 6. Auto-enter Debian whenever Termux opens
touch "$HOME/.bashrc"
if ! grep -q "proot-distro login debian" "$HOME/.bashrc"; then
    cat << 'AUTO_DEBIAN' >> "$HOME/.bashrc"

# Auto-launch Debian proot environment on interactive Termux start
if [[ $- == *i* ]] && command -v proot-distro >/dev/null 2>&1; then
    exec proot-distro login debian --shared-tmp
fi
AUTO_DEBIAN
fi

echo "Setup complete! Restart Termux (or run 'proot-distro login debian') to enter your Linux DevOps environment."
