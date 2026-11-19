# Termux Desktop Dotfiles & Setup

Automated bootstrap for a **Termux** development environment on **Android Desktop** (DeX / Desktop Mode). Installs **Git**, **OpenSSH**, **Neovim (LazyVim)**, **Starship**, **tmux**, **fzf**, **kubectl**, **kubie**, and **chezmoi**, configures GitHub SSH & Git identity, applies your dotfiles, and clones all of your GitHub repositories into `~/projects/GitHub.com/<username>/`.

---

## 1. Install Termux & Companion Apps on Android

Install from **F-Droid** or **GitHub Releases** (do **not** use the outdated Google Play Store version):
* [Termux on F-Droid](https://f-droid.org/packages/com.termux/)
* [Termux:API on F-Droid](https://f-droid.org/packages/com.termux.api/) *(Required so Neovim yanks/pastes sync with the Android desktop clipboard)*

---

## 2. Android OS & Developer Options (Recommended for Desktop)

To prevent Android from killing background terminal processes or Neovim LSP servers while you work in other desktop windows:

1. **Disable Child Process Restrictions (Android 14+):**
   * Open Android **Settings → About phone** and tap **Build number** 7 times to unlock Developer Options.
   * Go to **Settings → System → Developer options** and enable **Disable child process restrictions** (reboot once after enabling).
2. **Unrestricted Battery:**
   * Go to **Settings → Apps → Termux → Battery** and select **Unrestricted**.

---

## 3. Place Your SSH Private Key in Termux Home

Copy your `id_rsa.key` file into Termux's home directory (`~`). If it is in your Android `Downloads` folder:

```bash
termux-setup-storage
cp ~/storage/downloads/id_rsa.key ~/id_rsa.key
```

---

## 4. Create and Run `setup-termux.sh`

1. Open a new script file in `vi`:
   ```bash
   vi ~/setup-termux.sh
   ```
2. Press **`i`** to enter Insert mode, copy [`setup-termux.sh`](./setup-termux.sh) from this repository, tap and hold the Termux screen, and select **Paste**.
3. Save and exit `vi`:
   * Press **`ESC`**, type `:wq`, and press **`Enter`**.
4. Run the setup script:
   ```bash
   bash ~/setup-termux.sh
   ```
5. Reload your shell and initialize Neovim plugins:
   ```bash
   source ~/.bashrc
   nvim
   ```

---

## 5. Managing Dotfiles with `chezmoi`

This repository uses [`chezmoi`](https://www.chezmoi.io/) with `.chezmoiroot` set to `home/`, meaning files inside `home/` map directly to `~/` (`dot_bashrc` → `~/.bashrc`, `dot_config/` → `~/.config/`).

### Pull and apply updates from GitHub
When you edit dotfiles on another machine or on GitHub.com, update your Termux environment with:
```bash
chezmoi update
```

### Edit a config file and push changes back to GitHub
1. Edit a managed dotfile (or add a new one):
   ```bash
   chezmoi edit ~/.bashrc
   # OR after editing ~/.bashrc directly:
   chezmoi re-add ~/.bashrc
   ```
2. Preview changes and apply them locally:
   ```bash
   chezmoi diff
   chezmoi apply
   ```
3. Commit and push to your `termux-dotfiles` repository:
   ```bash
   chezmoi cd
   git add .
   git commit -m "Update dotfiles"
   git push
   exit
   ```

---

## 6. Quick Desktop Cheatsheet

* **`Ctrl + R`:** Fuzzy-search command history (`fzf`)
* **`Ctrl + T` (Termux):** Open a new terminal tab (`Ctrl + Tab` to switch tabs)
* **`Ctrl + Alt + C` / `Ctrl + Alt + V`:** Copy / Paste in Termux on a physical keyboard
* **`t`:** Start or re-attach to a mouse-enabled `tmux` session
* **`Space` (in Neovim):** Open the interactive shortcut menu (`Space + e` for file tree, `Space + Space` to find files)
* **`kc` / `kcn`:** Switch Kubernetes context (`kubie ctx`) or namespace (`kubie ns`) interactively
* **`k` / `kgp`:** `kubectl` shortcuts (`k get pods`, `k logs -f`, etc.)
