# ssh-v2ray-manager
# SSH/V2Ray Manager with Auto Renew and Telegram Notification

Script ini untuk generate akun SSH/V2Ray otomatis dengan fitur:  
- Pilihan server FastSSH, SSHOcean, SSHStores  
- Auto cek expired, auto renew akun  
- Pilihan notifikasi via Telegram (bot token + chat ID)  
- Save konfigurasi otomatis ke `.ehi` dan `.hc` di folder `/sdcard/ssh_accounts`  
- Payload HTTP custom & SSL bypass WAF  
- Bisa dijalankan di Termux  

---

## Cara Pakai

1. Clone repo atau download script:
---

Kamu tinggal buat file `README.md` di folder repo kamu, isi dengan ini, lalu commit & push ke GitHub.

Kalau mau saya bantu buatkan juga perintah git lengkapnya, bilang ya!

   ```bash
   git clone https://github.com/username/ssh-v2ray-manager.git
   cd ssh-v2ray-manager
chmod +x ssh_v2ray_manager.sh
./ssh_v2ray_manager.sh
