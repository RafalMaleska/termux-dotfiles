#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DOTFILES_REPO="termux-dotfiles"
KEY_PATH="$HOME/id_rsa.key"
SSH_DIR="$HOME/.ssh"
TARGET_KEY="$SSH_DIR/id_rsa"
CONFIG_FILE="$SSH_DIR/config"

# 1. Verify id_rsa.key exists in Termux's home directory
if [[ ! -f "$KEY_PATH" ]]; then
    echo "Error: $KEY_PATH not found."
    echo "Place id_rsa.key in your Termux home folder (~) before running this script."
    exit 1
fi

# 2. Update packages and install git, openssh, neovim, starship, chezmoi, curl, and jq
echo "Updating packages and installing dependencies..."
pkg update -y && pkg upgrade -y
pkg install -y git openssh neovim starship chezmoi curl jq

# 3. Create ~/.ssh, move the key, and set strict permissions
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

mv "$KEY_PATH" "$TARGET_KEY"
chmod 600 "$TARGET_KEY"

# 4. Configure SSH for GitHub
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

# 5. Add GitHub host key to known_hosts
ssh-keyscan -t ed25519,rsa github.com >> "$SSH_DIR/known_hosts" 2>/dev/null
chmod 644 "$SSH_DIR/known_hosts"

# 6. Authenticate via SSH key and extract GitHub username automatically
echo "Authenticating with GitHub using your SSH key..."
SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
echo "$SSH_OUTPUT"

GITHUB_USER=$(echo "$SSH_OUTPUT" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')

if [[ -z "$GITHUB_USER" ]]; then
    echo "Error: Could not detect GitHub username from SSH output. Check your SSH key."
    exit 1
fi

echo "Detected GitHub user: $GITHUB_USER"

# 7. Configure Git identity and push defaults automatically
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

# 8. Create ~/projects/GitHub.com/<username>
PROJECTS_DIR="$HOME/projects/GitHub.com/$GITHUB_USER"
mkdir -p "$PROJECTS_DIR"

# 9. Initialize and apply dotfiles via chezmoi over SSH
echo "Cloning and applying dotfiles from git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git..."
chezmoi init --apply "git@github.com:${GITHUB_USER}/${DOTFILES_REPO}.git"

# 10. Clone all repositories into ~/projects/GitHub.com/<username>/
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

# 11. Ensure ~/.bashrc exists and initializes Starship
touch "$HOME/.bashrc"
if ! grep -q "starship init bash" "$HOME/.bashrc"; then
    cat << 'BASHRC' >> "$HOME/.bashrc"

# Initialize Starship prompt
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
BASHRC
fi

echo "Setup complete! All repositories are in $PROJECTS_DIR"
echo "Restart Termux or run 'source ~/.bashrc' to load Starship."
