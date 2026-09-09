# Deploy by Mizyal

Universal PHP deployment system untuk Ubuntu server: CLI menu di terminal + script khusus SOLIDES.

Repo resmi script: `https://github.com/Mizyal13/deploy-by-mizyal`

## Cara Pakai (di server, sebagai root)

**Bootstrap pertama** (sekali saja — download semua script ke `/opt/deploy-by-mizyal` dan buat command global):

```bash
sudo curl -fsSL https://raw.githubusercontent.com/Mizyal13/deploy-by-mizyal/main/main.sh | sudo bash
```

**Jalankan menu** kapan pun:

```bash
sudo deploybymizyal
```

## Menu

| Opsi | Nama | Fungsi |
|------|------|--------|
| 1 | Install Server | Install stack server (Apache, PHP-FPM, MySQL, Composer) + deploy project baru (14 langkah) |
| 2 | Add Project | Tambah project tambahan di server yang sudah ter-install |
| 3 | Remove Project | Hapus project tertentu (config Apache, file, opsi DB) |
| 4 | Server Status | Quick check Apache, PHP-FPM, MySQL |
| 5 | Diagnostics | Full diagnostic: project, disk, error log, SSL expiry, firewall |
| 6 | Full Reset | Hapus SEMUA (uninstall Apache/PHP/MySQL, semua DB; SSH dipertahankan) |
| 7 | Deploy SOLIDES | Deploy khusus project SOLIDES (AHP supplier selection) |
| 8 | Update SOLIDES | Tarik commit terbaru SOLIDES + restore kredensial + permission |
| 9 | Setup Cloudflare Tunnel (Login) | Login Cloudflare → buat tunnel + subdomain otomatis + service |
| 10 | Update Scripts | Re-download semua script dari GitHub (upgrade CLI) |
| 11 | Exit | Keluar menu |

## Script SOLIDES

Repository: `https://github.com/hanafi0508/SPKSOLIDES.git` (native PHP + MySQLi, AHP supplier).

### Deploy pertama (menu 7, atau langsung)

**Sebelumnya:** setup tunnel dulu lewat menu **9** (Setup Cloudflare Tunnel) — login Cloudflare, otomatis dibuatkan tunnel + subdomain (mis. `solides.example.com`).

```bash
sudo bash deploy-solides.sh
```

Script hanya meminta **domain** yang sudah di-setup di menu 9. Tidak ada urusan token/Cloudflare di script ini — akses publik & HTTPS ditangani sepenuhnya oleh tunnel (Cloudflare Universal SSL). Kredensial dibuat otomatis, tampil di akhir, dan disimpan di `/root/solides-credentials.txt`.

> Catatan: firewall hanya membuka SSH; port web (80/443) tidak diekspos ke publik karena semua lewat tunnel.

### Update setelah ada perubahan code (menu 8, atau langsung)

```bash
sudo bash update-solides.sh
```

Menarik code terbaru otomatis (tanpa reset). Kredensial dibackup lalu ditulis ulang ke `.env`
(satu-satunya sumber konfigurasi — `database.local.php` tidak dipakai lagi), permission diperbaiki
(`.env` dibaca `www-data`, mode 640), dan menawarkan reset DB opsional.

## File Script

| File | Fungsi |
|------|--------|
| `main.sh` | Entry point CLI — bootstrap install + menu utama |
| `install.sh` | Install server Apache/PHP/MySQL/Composer + deploy project |
| `projectadd.sh` | Tambah project ke server |
| `projectremove.sh` | Hapus project dari server |
| `diagnostics.sh` | Status & full diagnostics server |
| `fullremove.sh` | Full reset server (hapus semuanya, SSH tetap) |
| `deploy-solides.sh` | Install server + deploy pertama SOLIDES (Apache, PHP-FPM, MySQL, phpMyAdmin, UFW, fail2ban, Cloudflare Tunnel) |
| `update-solides.sh` | Update project SOLIDES ke commit terbaru + restore kredensial + permission |
| `setup-tunnel.sh` | Login Cloudflare → buat tunnel + subdomain (CNAME otomatis) + pasang service |
