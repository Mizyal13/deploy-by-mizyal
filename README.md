# Deploy by Mizyal

One script to setup a fresh Ubuntu server and deploy PHP websites. Supports Laravel, Composer, and plain PHP.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/mizyal13/deploy-by-mizyal/main/main.sh | sudo bash
```

After installation, you can run it anytime:

```bash
deploybymizyal
```

## What It Does

- Installs Apache2, PHP (with common extensions), MySQL, Composer
- Clones your project from Git
- Creates database and user
- Configures Apache VirtualHost with PHP-FPM
- Auto-detects framework (Laravel / Composer / PHP Native)
- Sets up UFW firewall and fail2ban
- Optional SSL via Certbot
- Optional admin account creation (bcrypt/md5/plain)

## Scripts

| Script | Description |
|--------|-------------|
| `main.sh` | Entry point - menu to access everything |
| `install.sh` | Full server setup + first project |
| `projectadd.sh` | Add new project to existing server |
| `projectremove.sh` | Remove a project |
| `fullremove.sh` | Reset server to fresh Ubuntu |
| `diagnostics.sh` | Health check and error scanner |

## Requirements

- Fresh Ubuntu 20.04+ server
- Root access
- A Git repository URL for your project

## Tested On

- Ubuntu 20.04, 22.04, 24.04, 26.04
- AMD64 and ARM64
