# Deploy by Mizyal

Script deployment otomatis untuk fresh Ubuntu server. Tinggal jalanin scriptnya, server langsung siap deploy website PHP. Support Laravel, Composer, dan PHP native.

## Cara Pakai

 langsung jalanin ini di server:

```bash
curl -fsSL https://raw.githubusercontent.com/mizyal13/deploy-by-mizyal/main/main.sh | sudo bash
```

abis itu kalau mau akses lagi tinggal ketik:

```bash
deploybymizyal
```

## Fitur

- Install Apache2, PHP (sama extensionnya), MySQL, Composer
- Clone project dari Git langsung ke /var/www/
- Buat database + user otomatis
- Config Apache VirtualHost sama PHP-FPM
- Auto detect framework (Laravel / Composer / PHP Native)
- Setup UFW firewall sama fail2ban
- SSL gratis via Certbot (kalau pilih domain)
- Bisa bikin akun admin pas deployment (bcrypt/md5/plain)

## Script Yang Ada

| Script | Fungsi |
|--------|--------|
| `main.sh` | Menu utama, akses semua fitur |
| `install.sh` | Install server fresh + project pertama |
| `projectadd.sh` | Tambah project baru di server yang udah ada |
| `projectremove.sh` | Hapus project |
| `fullremove.sh` | Reset server balik ke fresh Ubuntu |
| `diagnostics.sh` | Cek status server + error scanner |

## Yang Dibutuhin

- Ubuntu 20.04 ke atas (fresh install)
- Akses root
- URL repository Git project lu

## Udah Di Test Di

- Ubuntu 20.04, 22.04, 24.04, 26.04
- AMD64 sama ARM64
