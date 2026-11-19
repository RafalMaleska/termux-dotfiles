# Termux Dotfiles & Setup

Automated bootstrap for a clean **Termux** environment on Android. Installs **Git**, **OpenSSH**, **Neovim**, **Starship**, and **chezmoi**, configures your GitHub SSH key, applies your dotfiles, and clones all of your GitHub repositories into `~/projects/GitHub.com/<username>/`.

---

## 1. Install Termux on Android

Install Termux from **F-Droid** or **GitHub Releases** (do **not** use the outdated Google Play Store version):
* [Termux on F-Droid](https://f-droid.org/packages/com.termux/)
* [Termux GitHub Releases](https://github.com/termux/termux-app/releases)

---

## 2. Place Your SSH Private Key in Termux Home

Copy your `id_rsa.key` file into Termux's home directory (`~`). If the file is in your Android `Downloads` folder, run:

```bash
termux-setup-storage
cp ~/storage/downloads/id_rsa.key ~/id_rsa.key
```

---

## 3. Create and Run `setup-termux.sh`

1. Open a new script file in `vi`:
   ```bash
   vi ~/setup-termux.sh
   ```
2. Press **`i`** to enter Insert mode, copy the contents of [`setup-termux.sh`](./setup-termux.sh) from this repository, tap and hold the Termux screen, and select **Paste**.
3. Save and exit `vi`:
   * Tap **`ESC`** (on the Termux extra keys bar)
   * Type `:wq` and press **`Enter`**
4. Run the setup script:
   ```bash
   bash ~/setup-termux.sh
   ```

---

## 4. Reload Your Shell

Once the script finishes authenticating with GitHub, applying your dotfiles via `chezmoi`, and cloning your repositories, reload Bash to activate Starship:

```bash
source ~/.bashrc
```

---

## Directory Layout After Setup

```text
~/
├── .ssh/
│   ├── config                      # Configured for github.com
│   └── id_rsa                      # Moved from ~/id_rsa.key (chmod 600)
└── projects/
    └── [GitHub.com/](https://GitHub.com/)
        └── <your-github-username>/
            ├── termux-dotfiles/
            └── <all-your-other-repos>/
```
