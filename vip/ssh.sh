#!/bin/bash
# Setup SSH WebSocket + UDPGW - Optimized for Amazon Linux 2023

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

DEPS_VERSION="deps-v2"
RELEASE_URL="https://github.com{DEPS_VERSION}"

clear
echo -e "${GREEN}▶️ Installing SSH + WebSocket on Amazon Linux 2023...${NC}"
sleep 1

# ================= ROOT CHECK =================
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] Script ini harus dijalankan sebagai root!${NC}"
   exit 1
fi

# ================= VALIDATION =================
if [[ ! -f ~/AutoscriptXRAY/config/issue.net ]]; then
    echo -e "${RED}[ERROR] issue.net not found!${NC}"
    exit 1
fi

# ================= INSTALL DEPENDENCY =================
echo -e "${GREEN}[INFO] Installing Dependencies via DNF...${NC}"
dnf update -y
dnf install -y \
    openssh-server \
    stunnel \
    wget \
    python3 \
    screen \
    git \
    golang \
    libtomcrypt-devel \
    libtommath-devel \
    gcc \
    make \
    zlib-devel \
    tar \
    bzip2 \
    procps-ng \
    iproute \
    policycoreutils-python-utils

mkdir -p /usr/local/bin

# ================= INSTALL DROPBEAR =================
echo ""
echo -e "${GREEN}[INFO] Installing Dropbear 2019.78...${NC}"
echo ""

systemctl stop dropbear 2>/dev/null || true
dnf remove -y dropbear >/dev/null 2>&1 || true

rm -f /usr/sbin/dropbear
rm -f /usr/bin/dbclient
rm -f /usr/bin/dropbearkey
rm -rf /tmp/dropbear-2019.78*

cd /tmp || exit 1

# Coba download dari HTTPS resmi, jika gagal gunakan mirror resmi
wget -qO /tmp/dropbear-2019.78.tar.bz2 "https://matt.ucc.asn.au/dropbear/releases/dropbear-2019.78.tar.bz2" || \
wget -qO /tmp/dropbear-2019.78.tar.bz2 "https://dropbear.nl" || {
    echo -e "${RED}[ERROR] Failed to download Dropbear source!${NC}"
    exit 1
}

# Validasi ukuran & format file sebelum ekstrak
if ! bzip2 -t /tmp/dropbear-2019.78.tar.bz2 >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Downloaded file is corrupted or not a valid bz2 archive!${NC}"
    exit 1
fi

tar -xjf /tmp/dropbear-2019.78.tar.bz2 -C /tmp
cd /tmp/dropbear-2019.78 || exit 1

./configure --prefix=/usr --sysconfdir=/etc/dropbear
make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" install

DROPBEAR_VER=$(dropbear -V 2>&1)
echo "$DROPBEAR_VER" | grep -q "2019.78" || {
    echo -e "${RED}[ERROR] Wrong Dropbear installed!${NC}"
    exit 1
}

# Bersihkan file kompilasi sementara
rm -rf /tmp/dropbear-2019.78*

# ================= HOSTKEY =================
mkdir -p /etc/dropbear

[ ! -f /etc/dropbear/dropbear_rsa_host_key ] && \
dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key

[ ! -f /etc/dropbear/dropbear_ecdsa_host_key ] && \
dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key

# ================= BANNER =================
cp ~/AutoscriptXRAY/config/issue.net /etc/issue.net
chmod 644 /etc/issue.net

# ================= DROPBEAR SERVICE =================
cat > /etc/systemd/system/dropbear.service <<EOF
[Unit]
Description=Dropbear SSH Server
After=network.target

[Service]
ExecStart=/usr/sbin/dropbear -E -F -p 109 -p 143 -W 65536 -b /etc/issue.net
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# ================= BUILD GO WS =================
echo ""
echo -e "${GREEN}[INFO] Building Go WebSocket Services...${NC}"
echo ""

if ! command -v go >/dev/null 2>&1; then
    dnf install -y golang
fi

cd ~/AutoscriptXRAY/internal/go || exit 1

go build -ldflags="-s -w" \
    -o /usr/local/bin/dropbearws \
    ./dropbear-ws || {
    echo -e "${RED}[ERROR] Failed to build dropbearws${NC}"
    exit 1
}

go build -ldflags="-s -w" \
    -o /usr/local/bin/stunnelws \
    ./stunnel-ws || {
    echo -e "${RED}[ERROR] Failed to build stunnelws${NC}"
    exit 1
}

chmod +x /usr/local/bin/dropbearws
chmod +x /usr/local/bin/stunnelws

cp ~/AutoscriptXRAY/internal/go/dropbear-ws.service \
   /etc/systemd/system/dropbear-ws.service

cp ~/AutoscriptXRAY/internal/go/stunnel-ws.service \
   /etc/systemd/system/stunnel-ws.service

# ================= INSTALL BADVPN UDPGW =================
echo ""
echo -e "${GREEN}[INFO] Building & Installing BadVPN UDPGW from source...${NC}"
echo ""

systemctl stop udpgw 2>/dev/null || true
pkill -9 -f badvpn-udpgw 2>/dev/null || true
rm -f /usr/local/bin/badvpn-udpgw
rm -rf /tmp/badvpn-build

# Install cmake jika belum tersedia di Amazon Linux 2023
dnf install -y cmake gcc make git

# Clone dan kompilasi hanya komponen udpgw agar cepat
git clone --depth 1 https://github.com/powermx/badvpn/tree/master /tmp/badvpn-build || {
    echo -e "${RED}[ERROR] Failed to clone BadVPN repository${NC}"
    exit 1
}

mkdir -p /tmp/badvpn-build/build
cd /tmp/badvpn-build/build || exit 1

cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1
make -j"$(nproc)"

cp udpgw/badvpn-udpgw /usr/local/bin/badvpn-udpgw || {
    echo -e "${RED}[ERROR] Failed to compile BadVPN UDPGW${NC}"
    exit 1
}

chmod +x /usr/local/bin/badvpn-udpgw

# Bersihkan folder kompilasi sementara
cd /root || true
rm -rf /tmp/badvpn-build

# ================= UDPGW SERVICE =================
cp ~/AutoscriptXRAY/sshws/udpgw.service \
   /etc/systemd/system/

# ================= INSTALL UDP CUSTOM =================
echo ""
echo -e "${GREEN}[INFO] Installing UDP Custom...${NC}"
echo ""

systemctl stop udp-custom 2>/dev/null || true
pkill -9 -f udp-custom 2>/dev/null || true
rm -f /usr/local/bin/udp-custom

wget -qO /usr/local/bin/udp-custom \
    "${RELEASE_URL}/udp-custom-linux-amd64" || {
    echo -e "${RED}[ERROR] Failed to download UDP Custom${NC}"
    exit 1
}

chmod +x /usr/local/bin/udp-custom

mkdir -p /etc/udp-custom
cp ~/AutoscriptXRAY/config/udp-custom.json \
   /etc/udp-custom/config.json

# ================= UDP CUSTOM SERVICE =================
cp ~/AutoscriptXRAY/sshws/udp-custom.service \
   /etc/systemd/system/

# ================= PERMISSION & SELINUX =================
chmod 644 /etc/systemd/system/dropbear.service
chmod 644 /etc/systemd/system/dropbear-ws.service
chmod 644 /etc/systemd/system/stunnel-ws.service
chmod 644 /etc/systemd/system/udpgw.service
chmod 644 /etc/systemd/system/udp-custom.service

# Pastikan SELinux mengizinkan systemd mengeksekusi binary custom
if command -v restorecon >/dev/null 2>&1; then
    restorecon -Rv /usr/local/bin/ /usr/sbin/dropbear /etc/systemd/system/ >/dev/null 2>&1 || true
fi

# ================= RELOAD =================
systemctl daemon-reload
systemctl daemon-reexec

# ================= ENABLE SERVICES =================
SERVICES=(
    "sshd"
    "dropbear"
    "dropbear-ws"
    "stunnel-ws"
    "udpgw"
    "udp-custom"
)

for svc in "${SERVICES[@]}"; do
    systemctl enable "$svc"
    systemctl restart "$svc"
done

# ================= RECHECK SERVICES ==============
sleep 2

for svc in "${SERVICES[@]}"; do
    systemctl is-active --quiet "$svc" || {
        echo -e "${RED}[ERROR] Service $svc failed to start! Cek log dengan: journalctl -u $svc -n 20${NC}"
        exit 1
    }
done

# ================= NOLOGIN WS ====================
cat > /etc/profile.d/no-login.sh <<'EOF'
#!/bin/bash
[[ "$USER" == "root" || "$USER" == "ec2-user" ]] && return
clear
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " SSH WS ACCOUNT ONLY"
echo " SHELL ACCESS DENIED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
sleep 2
pkill -9 -u "$USER"
EOF

chmod +x /etc/profile.d/no-login.sh

# ================= INSTALL LOG =================
cat >> /root/log-install.txt <<EOF
━━━━━━━━━━━━━━━━━━━━━━
SSH PANEL
━━━━━━━━━━━━━━━━━━━━━━
OpenSSH           : 22
Dropbear          : 109,143
SSH Websocket     : 2082
SSH SSL Websocket : 2096
BadVPN UDPGW      : 7300
Port UdpSSH       : 1-65535
━━━━━━━━━━━━━━━━━━━━━━
EOF

# ================= DONE =================
clear
echo ""
echo -e "${GREEN}[ OK ] SSH + WS + UDPGW Installed on Amazon Linux 2023${NC}"
echo ""
ss -tulnp | grep -E '22|109|143|2082|2096|7300|36712'
echo ""
echo -e "${GREEN}[INFO] Service Status:${NC}"
systemctl --no-pager --type=service | \
grep -E 'dropbear|sshd|udpgw|udp-custom|dropbear-ws|stunnel-ws'
echo ""
dropbear -V
echo ""
