# Deploy SOLIDES

Script deployment SOLIDES (native PHP + MySQLi, AHP supplier) di fresh Ubuntu server. Repo: `https://github.com/hanafi0508/SPKSOLIDES.git`.

## Cara Pakai

**Deploy pertama** (di server, sebagai root):

```bash
sudo bash deploy-solides.sh
```

Saat diminta, isi **domain** yang sudah DNS-only (grey cloud) ke IP server. Kredensial dibuat otomatis, tampil di akhir, dan disimpan di `/root/solides-credentials.txt`.

**Setelah ada perubahan code** (commit & push baru di GitHub), jalankan di server:

```bash
sudo bash update-solides.sh
```

Bagian ini menarik code terbaru tanpa me-rusak `config/database.local.php` (kredensial server), memperbaiki permission, dan menawarkan reset DB (opsional, hati-hati: `init.sql` menghapus semua data).

## File Script

| File | Fungsi |
|------|--------|
| `deploy-solides.sh` | Install server (Apache, PHP-FPM, MySQL, phpMyAdmin, UFW, fail2ban, SSL) + deploy pertama SOLIDES |
| `update-solides.sh` | Update project di server ke commit terbaru dari GitHub + restore kredensial + permission |
