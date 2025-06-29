#!/data/data/com.termux/files/usr/bin/bash

clear
echo "🔰 SSH/V2Ray Manager + Auto Renew + Server Fallback + Optional Telegram Notify | Termux 🔰"
echo "=============================================================================================="
pkg install -y python pyqrcode pypng > /dev/null 2>&1

read -p "Mau pakai Telegram Notifikasi? (y/n): " USE_TELEGRAM
USE_TELEGRAM=$(echo "$USE_TELEGRAM" | tr '[:upper:]' '[:lower:]')

if [ "$USE_TELEGRAM" = "y" ]; then
    read -p "Masukkan Telegram Bot Token: " TELEGRAM_BOT_TOKEN
    read -p "Masukkan Telegram Chat ID: " TELEGRAM_CHAT_ID
else
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
fi

python - << EOF
import base64, json, uuid, secrets, os, subprocess, requests
from datetime import datetime, timedelta
import sys

FOLDER = "/sdcard/ssh_accounts"
if not os.path.exists(FOLDER):
    os.makedirs(FOLDER)

TELEGRAM_BOT_TOKEN = "${TELEGRAM_BOT_TOKEN}"
TELEGRAM_CHAT_ID = "${TELEGRAM_CHAT_ID}"

servers = [
    {"site":"FastSSH",  "name":"SG FastSSH",   "domain":"sg1.fastssh.com",  "max_user":5},
    {"site":"FastSSH",  "name":"US FastSSH",   "domain":"us1.fastssh.com",  "max_user":5},
    {"site":"SSHOcean", "name":"SG SSHOcean",  "domain":"sgp.sshelocean.com","max_user":5},
    {"site":"SSHStores","name":"SG SSHStores", "domain":"sg.sshstores.net",  "max_user":5},
]

def telegram_send(message):
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return False
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    data = {"chat_id": TELEGRAM_CHAT_ID, "text": message, "parse_mode": "Markdown"}
    try:
        r = requests.post(url, data=data, timeout=10)
        return r.status_code == 200
    except Exception as e:
        print("Gagal kirim notifikasi Telegram:", e)
        return False

def ping(host):
    try:
        output = subprocess.check_output(
            ["ping", "-c", "1", "-W", "1", host],
            stderr=subprocess.STDOUT,
            universal_newlines=True
        )
        for line in output.split('\\n'):
            if 'time=' in line:
                time_ms = line.split('time=')[1].split(' ')[0]
                return float(time_ms)
    except:
        return float('inf')
    return float('inf')

def load_accounts():
    accounts = []
    for filename in os.listdir(FOLDER):
        if filename.endswith(".hc"):
            path = os.path.join(FOLDER, filename)
            try:
                with open(path) as f:
                    data = json.load(f)
                    accounts.append({"file":path, "data":data})
            except:
                pass
    return accounts

def count_users_per_server(accounts):
    counts = {srv['domain']:0 for srv in servers}
    for acc in accounts:
        srv_domain = acc['data'].get('host')
        if srv_domain in counts:
            counts[srv_domain] += 1
    return counts

def is_expiring_soon(expired_str):
    try:
        exp_date = datetime.strptime(expired_str, "%Y-%m-%d %H:%M:%S")
        now = datetime.now()
        return 0 <= (exp_date - now).total_seconds() <= 86400  # ≤ 1 hari
    except:
        return False

def is_expired(expired_str):
    try:
        exp_date = datetime.strptime(expired_str, "%Y-%m-%d %H:%M:%S")
        return datetime.now() > exp_date
    except:
        return True

def generate_account(username, srv, days=7):
    password = secrets.token_urlsafe(8)
    created = datetime.now()
    expire = created + timedelta(days=days)

    vm = {
        "v":"2","ps":f"{username}-v2ray","add":srv['domain'],"port":"443",
        "id":str(uuid.uuid4()),"aid":"0","net":"ws","type":"none",
        "host":srv['domain'],"path":"/v2ray","tls":"tls"
    }
    vmj = json.dumps(vm, indent=2)
    vmlink = "vmess://" + base64.b64encode(vmj.encode()).decode()

    p_no = (f"GET / HTTP/1.1\r\nHost: {srv['domain']}\r\n"
            f"User-Agent: Mozilla/5.0 (Android)\r\n"
            f"X-Online-Host: {srv['domain']}\r\n"
            f"X-Forwarded-Host: {srv['domain']}\r\n"
            f"X-Forwarded-For:127.0.0.1\r\n"
            f"Upgrade-Insecure-Requests:1\r\nConnection:Keep-Alive\r\n\r\n")

    p_ssl = (f"CONNECT {srv['domain']}:443 HTTP/1.1\r\nHost: {srv['domain']}\r\n"
             f"X-Online-Host: {srv['domain']}\r\n"
             f"X-Forwarded-Host: {srv['domain']}\r\n"
             f"X-Forwarded-For:127.0.0.1\r\n"
             f"User-Agent:Mozilla/5.0(Android)\r\n"
             f"Upgrade-Insecure-Requests:1\r\nConnection:keep-alive\r\n\r\n")

    ehi = os.path.join(FOLDER, f"config_{username}.ehi")
    hc  = os.path.join(FOLDER, f"config_{username}.hc")

    with open(ehi, "w") as f:
        f.write(f"# Host: {srv['domain']}:443\nUsername: {username}\nPassword: {password}\nCreated: {created}\nExpired: {expire}\nPayload:\n{p_ssl}")
    with open(hc, "w") as f:
        json.dump({
            "host":srv['domain'],
            "port":443,
            "username":username,
            "password":password,
            "created":created.strftime("%Y-%m-%d %H:%M:%S"),
            "expired":expire.strftime("%Y-%m-%d %H:%M:%S"),
            "payload":p_no,
            "vmess": vmj,
            "vmess_link": vmlink
        }, f, indent=2)

    if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
        msg = (
            f"*SSH/V2Ray Account Generated*\n"
            f"Server: {srv['name']} ({srv['domain']})\n"
            f"Username: {username}\n"
            f"Password: {password}\n"
            f"Created: {created.strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"Expired: {expire.strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"VMess Link:\n{vmlink}"
        )
        telegram_send(msg)

    return (username, password, created, expire, vmj, vmlink, ehi, hc)

def select_server(counts):
    ping_results = {}
    for idx, srv in enumerate(servers):
        ping_results[idx] = ping(srv['domain'])
    sorted_servers = sorted(servers, key=lambda s: ping_results[servers.index(s)])
    for srv in sorted_servers:
        if counts[srv['domain']] < srv['max_user']:
            return srv
    return None

print("🔰 Mulai pengecekan akun dan server...")

accounts = load_accounts()
counts = count_users_per_server(accounts)

print("\\n🔰 Ping test server:")
for srv in servers:
    p = ping(srv['domain'])
    print(f"{srv['name']} ({srv['domain']}): {p if p != float('inf') else 'Gagal'} ms")
print("\\n🔰 Jumlah akun per server:")
for srv in servers:
    print(f"{srv['name']}: {counts[srv['domain']]} / {srv['max_user']} akun")

srv = select_server(counts)
if not srv:
    sys.exit("❌ Semua server penuh! Tidak bisa generate akun baru.")

print(f"\\nRekomendasi server untuk generate: {srv['name']} ({srv['domain']})")

renewed = False
for acc in accounts:
    data = acc['data']
    username = data.get("username")
    expired_str = data.get("expired", "1970-01-01 00:00:00")
    if is_expired(expired_str) or is_expiring_soon(expired_str):
        print(f"⚠ Akun {username} expired atau hampir expired, generate ulang...")
        u,p,c,e,vmj,vml,ehi,hc = generate_account(username, srv)
        print(f"✅ Akun baru: {u} / Pass: {p} | Expired: {e}")
        renewed = True

if not accounts or not renewed:
    u = input("Masukkan username baru: ").strip()
    u,p,c,e,vmj,vml,ehi,hc = generate_account(u, srv)
    print(f"✅ Akun baru: {u} / Pass: {p} | Expired: {e}")

print(f"\\n📂 Semua file konfigurasi disimpan di folder: {FOLDER}")
EOF
