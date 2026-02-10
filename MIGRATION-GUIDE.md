# Migration Guide

## Disaster recovery

If you lose your laptop, you need exactly two things from memory:

1. AWS root credentials (email + password) — gets you into the console,
   which gets you to Lightsail, which means Vaultwarden at
   git.barrettruth.com is reachable
2. Vaultwarden master password — unlocks everything else (GitHub, email,
   etc.)

If you have 2FA on either of these via an authenticator app, you also
need recovery codes. Print them. Store them somewhere physical that
isn't your laptop.

All SSH keys, GPG keys, and .pem files are stored as attachments in
Vaultwarden. Restoring them is step 10 below.

## Pre-migration (do this on Arch before wiping)

### Upload keys to Vaultwarden

Open git.barrettruth.com and create a secure note entry for your keys.

Export your GPG private key:

```sh
gpg --export-secret-keys --armor A6C96C9349D2FC81 > /tmp/gpg-private.asc
```

Attach all seven files to the vault entry:

| File | Path |
|------|------|
| `id_ed25519` | `~/.ssh/id_ed25519` |
| `id_ed25519.pub` | `~/.ssh/id_ed25519.pub` |
| `git-keypair.pem` | `~/.ssh/git-keypair.pem` |
| `git-keypair-old.pem` | `~/.ssh/git-keypair-old.pem` |
| `uva_key` | `~/.ssh/uva_key` |
| `uva_key.pub` | `~/.ssh/uva_key.pub` |
| `gpg-private.asc` | `/tmp/gpg-private.asc` |

Verify all attachments are downloadable, then clean up:

```sh
rm /tmp/gpg-private.asc
```

By storing the same keys, the key IDs in `git.nix` stay valid, GitHub
doesn't need updating, and git signing works immediately after restore.

### Store AWS credentials in Vaultwarden

Create a separate secure note entry for AWS credentials. Store each
profile's access key ID and secret access key as fields (or in the
note body):

- `barrett` — `AKIA6ODU5IDCSC3ZGB2D`
- `projecta10` — `AKIA6ODU5IDC3T6IVW6Y`
- `tcf` — `AKIAVY2PGOP7SHEKVCFP`

Include both the access key ID and secret access key for each profile.
The AWS config file (region, output format) is managed declaratively
in `shell.nix` — only the credentials are secret.

### Push this repo

```sh
cd ~/nix-config
git push
```

## Fresh install from zero

### 1. Flash the installer

Download the NixOS minimal ISO from https://nixos.org/download (x86_64).

```sh
dd bs=4M if=nixos-minimal-*.iso of=/dev/sdX status=progress oflag=sync
```

### 2. Boot and connect to WiFi

Boot from USB (F12 for boot menu on XPS 15).

```sh
iwctl
[iwd]# station wlan0 scan
[iwd]# station wlan0 get-networks
[iwd]# station wlan0 connect <SSID>
```

Verify: `ping nixos.org`

### 3. Partition

```sh
lsblk -f
```

#### Option A: fresh partition table

```sh
fdisk /dev/nvme0n1

# 1. EFI System partition — 512M
# 2. Linux swap — match your RAM
# 3. Linux filesystem — rest of disk

mkfs.fat -F 32 /dev/nvme0n1p1
mkswap /dev/nvme0n1p2
mkfs.ext4 -L nixos /dev/nvme0n1p3

mount /dev/nvme0n1p3 /mnt
mkdir -p /mnt/boot/efi
mount /dev/nvme0n1p1 /mnt/boot/efi
swapon /dev/nvme0n1p2
```

#### Option B: reuse existing partitions

```sh
mkfs.ext4 -L nixos /dev/nvme0n1pX    # formats root, wipes the old OS

mount /dev/nvme0n1pX /mnt
mkdir -p /mnt/boot/efi
mount /dev/nvme0n1pY /mnt/boot/efi
swapon /dev/nvme0n1pZ
```

### 4. Generate hardware config

```sh
nixos-generate-config --root /mnt
```

This produces `/mnt/etc/nixos/hardware-configuration.nix`. You need this
file — it describes your specific disk UUIDs, kernel modules, and
firmware. The generated `configuration.nix` next to it is not used.

### 5. Clone the repo

```sh
nix-shell -p git
git clone https://github.com/barrettruth/nix-config /mnt/home/barrett/nix-config
```

Copy the hardware config into place:

```sh
cp /mnt/etc/nixos/hardware-configuration.nix /mnt/home/barrett/nix-config/hosts/xps15/
```

### 6. Copy fonts (optional, can be done later)

Fonts are proprietary and not in the repo. The build will succeed
without them — home-manager prints a warning and fonts fall back to
system defaults. When you're ready, populate `~/nix-config/fonts/`:

- Copy from a USB drive
- Copy from a backup
- Download from wherever you originally purchased them
- Pull from another machine via scp

```sh
cp -r /path/to/your/fonts /mnt/home/barrett/nix-config/fonts/
```

The `fonts/` directory is gitignored and symlinked to
`~/.local/share/fonts` at activation time.

### 7. Install

```sh
nixos-install --flake /mnt/home/barrett/nix-config#xps15
```

This builds the entire system (kernel, drivers, services, user
environment, home-manager) in one shot. It will ask you to set the root
password at the end.

### 8. Reboot and set user password

```sh
reboot
```

Remove the USB. Log in as root, then:

```sh
passwd barrett
logout
```

Log in as barrett.

### 9. Fix ownership

The install created `~/nix-config` as root. Fix it:

```sh
sudo chown -R barrett:users ~/nix-config
```

### 10. Restore keys from Vaultwarden

Open Zen browser and go to git.barrettruth.com. Log in with your
master password. Open the vault entry containing your keys and download
all attachments.

#### SSH keys

```sh
mkdir -p ~/.ssh
cp ~/Downloads/id_ed25519 ~/.ssh/
cp ~/Downloads/id_ed25519.pub ~/.ssh/
cp ~/Downloads/git-keypair.pem ~/.ssh/
cp ~/Downloads/git-keypair-old.pem ~/.ssh/
cp ~/Downloads/uva_key ~/.ssh/
cp ~/Downloads/uva_key.pub ~/.ssh/
```

Permissions are fixed automatically by the activation script in
`git.nix` on the next rebuild. If you want them right now:

```sh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519 ~/.ssh/git-keypair.pem ~/.ssh/git-keypair-old.pem ~/.ssh/uva_key
chmod 644 ~/.ssh/id_ed25519.pub ~/.ssh/uva_key.pub
```

Set the repo remote to SSH for push access:

```sh
cd ~/nix-config
git remote set-url origin git@github.com:barrettruth/nix-config.git
```

#### GPG key

```sh
gpg --import ~/Downloads/gpg-private.asc
gpg --edit-key A6C96C9349D2FC81 trust
```

Select trust level 5 (ultimate), then `quit`. The key ID matches what's
in `git.nix`, so git signing works immediately.

#### AWS credentials

Open the AWS credentials entry in Vaultwarden and create the
credentials file. The config file (region, output) is managed by
`shell.nix` — only the credentials are manual.

```sh
mkdir -p ~/.config/aws
cat > ~/.config/aws/credentials << 'EOF'
[barrett]
aws_access_key_id = <from vaultwarden>
aws_secret_access_key = <from vaultwarden>
[projecta10]
aws_access_key_id = <from vaultwarden>
aws_secret_access_key = <from vaultwarden>
[tcf]
aws_access_key_id = <from vaultwarden>
aws_secret_access_key = <from vaultwarden>
EOF
chmod 600 ~/.config/aws/credentials
```

#### Clean up

Delete the downloaded key files from `~/Downloads/`.

### 11. Rebuild

After all manual steps are done:

```sh
cd ~/nix-config
sudo nixos-rebuild switch --flake .#xps15
```

### 12. Verify

- Terminal opens (ghostty)
- Neovim works and plugins install on first launch
- Browser opens (zen)
- Waybar shows at top
- Audio works (XF86 keys)
- Git push works (SSH)
- Git commits are signed (GPG)

## What's automated vs. what's manual

### Automated (handled by the flake)

- All packages and their exact versions
- Zsh, tmux, fzf, direnv, lf configuration
- Ghostty terminal configuration
- Hyprland, waybar, rofi, dunst, hypridle, hyprlock, hyprpaper
- Git config, aliases, ignore patterns
- SSH config (host definitions, not keys)
- GPG agent config (not the keys themselves)
- Keyd keyboard remapping
- NVIDIA drivers and prime offload
- Pipewire audio stack
- Docker and libvirt
- Systemd services and timers
- XDG directories and MIME associations
- Scripts in PATH via ~/nix-config/scripts
- AWS config (region, output format)
- Directory creation (~/dev, ~/dl, ~/img, ~/wp)
- Cloning this repo to ~/nix-config on first activation
- Wallpaper symlinks from the repo to ~/img/screen
- Daily flake input updates

### Manual (you must do these yourself)

- Flash and boot the installer
- Partition and mount disks
- Generate hardware-configuration.nix
- Set root and user passwords
- Restore SSH keys, GPG key, and .pem files from Vaultwarden
- Restore AWS credentials from Vaultwarden
- Copy fonts into nix-config/fonts/ (optional, can be done later)
- Restore browser profile (~/.zen) if you want tabs/extensions back
