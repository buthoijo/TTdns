#!/bin/bash
R="\e[1;31m"
G="\e[92;1m"
Y="\e[33m"
B="\e[34m"
C="\e[36m"
M="\e[35m"
W="\e[37;1m"
NC="\e[0m"
FONT="\033[0m"
GB="\033[42;37m"
RB="\033[41;37m"
OK="${G}--->${FONT}"
ERROR="${R}[ERROR]${FONT}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none
export UCF_FORCE_CONFFNEW=1
export DEBCONF_NONINTERACTIVE_SEEN=true
APT_ARGS=(-y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew")

if ! command -v sudo >/dev/null 2>&1; then
    sudo() { "$@"; }
fi

configure_noninteractive() {
    mkdir -p /etc/apt/apt.conf.d
    cat >/etc/apt/apt.conf.d/99autoscript-vip-noninteractive <<'EOF'
Dpkg::Options {
   "--force-confdef";
   "--force-confnew";
}
APT::Get::Assume-Yes "true";
APT::Get::force-yes "false";
EOF
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections 2>/dev/null || true
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections 2>/dev/null || true
    echo keyboard-configuration keyboard-configuration/model select "Generic 105-key PC" | debconf-set-selections 2>/dev/null || true
    echo keyboard-configuration keyboard-configuration/layout select "English (US)" | debconf-set-selections 2>/dev/null || true
    echo keyboard-configuration keyboard-configuration/variant select "English (US)" | debconf-set-selections 2>/dev/null || true
    echo keyboard-configuration keyboard-configuration/optionscode string "" | debconf-set-selections 2>/dev/null || true
    echo libc6 libraries/restart-without-asking boolean true | debconf-set-selections 2>/dev/null || true
}

clear
echo -e "${Y}----------------------------------------------------------${NC}"
echo -e " Autoscript VPN VIP - Ubuntu 22.04/24.04/26.04.1 & Debian 12"
echo -e " Repository : zaker240091-bit/autoscript-vip (Fixed WS)"
echo -e "${Y}----------------------------------------------------------${NC}"

if [ "${EUID}" -ne 0 ]; then
    echo -e "${ERROR} Jalankan sebagai root: sudo -i lalu ulangi instalasi."
    exit 1
fi

if [ -r /etc/os-release ]; then
    . /etc/os-release
else
    echo -e "${ERROR} /etc/os-release tidak ditemukan."
    exit 1
fi

os_supported() {
    local vid="${VERSION_ID%%.*}"
    case "${ID}" in
        ubuntu)
            case "${VERSION_ID}" in
                20.04|22.04|24.04|26.04) return 0 ;;
            esac
            ;;
        debian)
            case "${vid}" in
                10|11|12|13) return 0 ;;
            esac
            ;;
    esac
    return 1
}

prepare_debian10_repo() {
    [ "${ID}" = "debian" ] && [ "${VERSION_ID%%.*}" = "10" ] || return 0
    print_install "Debian 10 EOL - beralih ke archive.debian.org"
    mkdir -p /etc/apt/apt.conf.d
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-valid-until
    rm -f /etc/apt/sources.list.d/buster*.list /etc/apt/sources.list.d/backports.list
    cat > /etc/apt/sources.list <<'EOF'
deb http://debian.org buster main contrib non-free
deb http://debian.org buster-backports main contrib non-free
deb http://debian.org-security buster/updates main contrib non-free
EOF
}

if os_supported; then
    :
else
    echo -e "${ERROR} OS tidak didukung. Didukung: Ubuntu 20.04/22.04/24.04/26.04 dan Debian 10/11/12/13. Terdeteksi: ${PRETTY_NAME:-unknown}"
    exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
    echo -e "${ERROR} Arsitektur tidak didukung. Script ini hanya untuk x86_64/amd64."
    exit 1
fi

configure_noninteractive
NET=$(ip -4 route ls | awk '/default/ {print $5; exit}')
export NET
export IP=$( curl -sS icanhazip.com )

function pasang_domain() {
    mkdir -p /var/lib/kyt /etc/xray /etc/slowdns
    echo "IP=${IP}" > /var/lib/kyt/ipvps.conf
    if [[ -n "${DOMAIN_VIP:-}" ]]; then
        echo "$DOMAIN_VIP" > /etc/xray/domain
        echo "$DOMAIN_VIP" > /root/domain
    fi
    if [[ -n "${NS_VIP:-}" ]]; then
        echo "$NS_VIP" > /etc/xray/dns
        echo "$NS_VIP" > /root/nsdomain
        echo "$NS_VIP" > /etc/slowdns/nsdomain
    fi
}

input_domain_ns() {
    clear
    echo -e "${Y}┌──────────────────────────────────────────┐${NC}"
    echo -e "${Y}│${NC}          ${G}INPUT DOMAIN & NS SLOWDNS${NC}        ${Y}│${NC}"
    echo -e "${Y}└──────────────────────────────────────────┘${NC}"
    echo ""
    while true; do
        read -rp "  Masukan Domain      : " DOMAIN_VIP
        DOMAIN_VIP=$(echo "$DOMAIN_VIP" | tr -d '[:space:]')
        [[ -n "$DOMAIN_VIP" && "$DOMAIN_VIP" == *.* ]] && break
    done
    while true; do
        read -rp "  Masukan NS SlowDNS  : " NS_VIP
        NS_VIP=$(echo "$NS_VIP" | tr -d '[:space:]')
        [[ -n "$NS_VIP" && "$NS_VIP" == *.* ]] && break
    done
    echo ""
    pasang_domain
}

input_domain_ns

clear
echo -e "${Y}----------------------------------------------------------${NC}"
echo -e " Dev > Script ${Y}(${NC}${G} Stable Edition ${NC}${Y})${NC}"
echo -e " This Will Quick Setup VPN Server On Your Server"
echo -e "${Y}----------------------------------------------------------${NC}"
echo ""
sleep 1

if [[ $( uname -m | awk '{print $1}' ) == "x86_64" ]]; then
    echo -e "${OK} Your Architecture Is Supported ( ${G}$( uname -m )${NC} )"
else
    echo -e "${ERROR} Your Architecture Is Not Supported ( ${Y}$( uname -m )${NC} )"
    exit 1
fi

if [[ $( cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g' ) == "ubuntu" ]]; then
    echo -e "${OK} Your OS Is Supported ( ${G}$( cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g' )${NC} )"
elif [[ $( cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g' ) == "debian" ]]; then
    echo -e "${OK} Your OS Is Supported ( ${G}$( cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g' )${NC} )"
else
    echo -e "${ERROR} Your OS Is Not Supported ( ${Y}$( cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g' )${NC} )"
    exit 1
fi

if [[ $IP == "" ]]; then
    echo -e "${ERROR} IP Address ( ${Y}Not Detected${NC} )"
else
    echo -e "${OK} IP Address ( ${G}$IP${NC} )"
fi

echo -e "${OK} Memulai instalasi tanpa prompt tambahan."
clear
if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root"
    exit 1
fi
if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo "OpenVZ is not supported"
    exit 1
fi
MYIP=$(curl -sS ://icanhazip.com)
echo -e "\e[32mloading...\e[0m"
clear

apt-get install "${APT_ARGS[@]}" ruby
gem install lolcat
apt-get install "${APT_ARGS[@]}" wondershaper || true
clear
REPO="${REPO:-https://githubusercontent.com}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fetch_file() {
    local rel="$1"
    local dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -f "${SCRIPT_DIR}/${rel}" ]; then
        cp -f "${SCRIPT_DIR}/${rel}" "$dst"
    elif [ -n "${REPO:-}" ]; then
        wget -q -O "$dst" "${REPO}${rel}" || curl -fsSL "${REPO}${rel}" -o "$dst"
    else
        echo "Error: ${rel} not found locally" >&2
        return 1
    fi
}

run_file() {
    local rel="$1"
    local tmp="/tmp/$(basename "$rel")"
    fetch_file "$rel" "$tmp"
    chmod +x "$tmp"
    bash "$tmp"
}

if [ -f "${SCRIPT_DIR}/media/srcbuild" ]; then
    source "${SCRIPT_DIR}/media/srcbuild"
fi

unify_versions() {
    clear
    print_install "Menyamakan versi service dari source resmi"
    if ! declare -F sb_nginx >/dev/null 2>&1; then
        echo -e "${Y} Modul srcbuild tidak ditemukan, versi mengikuti repo OS${NC}"
        sleep 2
        return 0
    fi
    local b
    for b in sb_nginx sb_haproxy sb_openvpn sb_dropbear; do
        if "$b"; then
            echo -e "${G} [OK]${NC} $b"
        else
            echo -e "${Y} [SKIP]${NC} $b gagal build, pakai binary repo OS"
        fi
    done
    if command -v nginx >/dev/null 2>&1 && ! nginx -t >/dev/null 2>&1; then
        [ -f /usr/sbin/nginx.repo ] && cp -f /usr/sbin/nginx.repo /usr/sbin/nginx
        echo -e "${Y} nginx hasil build menolak config, kembali ke versi repo${NC}"
    fi
    if command -v haproxy >/dev/null 2>&1 && ! haproxy -f /etc/haproxy/haproxy.cfg -c -q >/dev/null 2>&1; then
        if [ -f /usr/sbin/haproxy.repo ]; then
            cp -f /usr/sbin/haproxy.repo /usr/sbin/haproxy
            echo -e "${Y} haproxy hasil build menolak config, kembali ke versi repo${NC}"
        fi
    fi
    for s in nginx haproxy dropbear openvpn-server@server-tcp openvpn-server@server-udp; do
        systemctl restart "$s" >/dev/null 2>&1 || true
    done
    sb_report
    print_success "Versi service seragam"
}

restart_enable() {
    systemctl daemon-reload >/dev/null 2>&1 || true
    for svc in "$@"; do
        systemctl enable --now "$svc" >/dev/null 2>&1 || systemctl restart "$svc" >/dev/null 2>&1 || true
    done
}

start=$(date +%s)
secs_to_human() {
    echo "Installation time : $((${1} / 3600)) hours $(((${1} / 60) % 60)) minute's $((${1} % 60)) seconds"
}
function print_ok() {
    echo -e "${OK} ${C} $1 ${FONT}"
}
function print_install() {
    echo -e "${G} =============================== ${FONT}"
    echo -e "${Y} # $1 ${FONT}"
    echo -e "${G} =============================== ${FONT}"
    sleep 1
}

function print_error() {
    echo -e "${ERROR} ${RB} $1 ${FONT}"
}

function print_success() {
    if [[ 0 -eq $? ]]; then
        echo -e "${G} =============================== ${FONT}"
        echo -e "${G} # $1 berhasil dipasang"
        echo -e "${G} =============================== ${FONT}"
        sleep 2
    fi
}

function is_root() {
    if [[ 0 == "$UID" ]]; then
        print_ok "Root user Start installation process"
    else
        print_error "The current user is not the root user, please switch to the root user and run the script again"
    fi
}

print_install "Membuat direktori xray"
mkdir -p /etc/xray

curl -s ifconfig.me > /etc/xray/ipvps
touch /etc/xray/domain
mkdir -p /var/log/xray
chown www-data.www-data /var/log/xray
chmod +x /var/log/xray
touch /var/log/xray/access.log
touch /var/log/xray/error.log
mkdir -p /var/lib/kyt >/dev/null 2>&1
while IFS=":" read -r a b; do
case $a in
"MemTotal") ((mem_used+=${b/kB})); mem_total="${b/kB}" ;;
"Shmem") ((mem_used+=${b/kB})) ;;
"MemFree" | "Buffers" | "Cached" | "SReclaimable")
mem_used="$((mem_used-=${b/kB}))"
;;
esac
done < /proc/meminfo
Ram_Usage="$((mem_used / 1024))"
Ram_Total="$((mem_total / 1024))"
export tanggal=$(date -d "0 days" +"%d-%m-%Y - %X")
export OS_Name=$( cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/PRETTY_NAME//g' | sed 's/=//g' | sed 's/"//g' )
export Kernel=$( uname -r )
export Arch=$( uname -m )
export IP=$( curl -s ipinfo.io )

function first_setup(){
timedatectl set-timezone Asia/Jakarta || true
configure_noninteractive
print_success "Directory Xray"
echo "Setup Dependencies ${PRETTY_NAME}"
prepare_debian10_repo
apt-get update -y
if [[ "${ID}" == "debian" && ("${VERSION_ID%%.}" == "12" || "${VERSION_ID%%.}" == "13") ]]; then
if ! grep -q "backports" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
echo "deb debian.org ${VERSION_CODENAME}-backports main" > /etc/apt/sources.list.d/backports.list
apt-get update -y >/dev/null 2>&1 || true
fi

apt-get install "${APT_ARGS[@]}" --no-install-recommends ca-certificates curl wget gnupg lsb-release debconf-utils apt-transport-https
else
apt-get install "${APT_ARGS[@]}" --no-install-recommends software-properties-common ca-certificates curl wget gnupg lsb-release debconf-utils apt-transport-https
fi
apt-get install "${APT_ARGS[@]}" haproxy
systemctl enable haproxy >/dev/null 2>&1 || true
}

clear
function nginx_install() {
if [[ $(cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g') == "ubuntu" ]]; then
print_install "Setup nginx For OS Is $(cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g')"
apt-get install "${APT_ARGS[@]}" nginx
elif [[ $(cat /etc/os-release | grep -w ID | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/ID//g') == "debian" ]]; then
print_install "Setup nginx For OS Is $(cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g')"
apt-get install "${APT_ARGS[@]}" nginx
else
echo -e " Your OS Is Not Supported ( ${Y}$(cat /etc/os-release | grep -w PRETTY_NAME | head -n1 | sed 's/=//g' | sed 's/"//g' | sed 's/PRETTY_NAME//g')${FONT} )"
fi
}

function base_package() {
clear
print_install "Menginstall Packet Yang Dibutuhkan"
apt-get install "${APT_ARGS[@]}" zip pwgen openssl netcat-openbsd socat cron bash-completion openssh-server
apt-get install "${APT_ARGS[@]}" figlet
apt-get update -y
apt-get upgrade "${APT_ARGS[@]}"
apt-get dist-upgrade "${APT_ARGS[@]}"
systemctl enable chronyd >/dev/null 2>&1 || true
systemctl restart chronyd >/dev/null 2>&1 || true
systemctl enable chrony >/dev/null 2>&1 || true
systemctl restart chrony >/dev/null 2>&1 || true
chronyc sourcestats -v
chronyc tracking -v
apt-get install "${APT_ARGS[@]}" ntpdate >/dev/null 2>&1 || true
ntpdate pool.ntp.org >/dev/null 2>&1 || true
apt-get install "${APT_ARGS[@]}" sudo
apt-get clean
apt-get autoremove "${APT_ARGS[@]}"
apt-get install "${APT_ARGS[@]}" debconf-utils
apt-get remove --purge "${APT_ARGS[@]}" exim4 || true
apt-get remove --purge "${APT_ARGS[@]}" ufw firewalld || true
apt-get install "${APT_ARGS[@]}" --no-install-recommends software-properties-common >/dev/null 2>&1 || true
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true |
debconf-set-selections
COMMON_PKGS="vnstat libnss3-dev libnspr4-dev pkg-config libpam0g-dev libcap-ng-dev libcap-ng-utils libselinux1-dev libcurl4-nss-dev flex bison make libnss3-tools libevent-dev bc rsyslog dos2unix zlib1g-dev libssl-dev libsqlite3-dev sed dirmngr libxml-parser-perl build-essential gcc g++ python3 python3-pip htop lsof tar wget curl ruby zip unzip p7zip-full libc6 util-linux msmtp-mta ca-certificates bsd-mailx iptables iptables-persistent netfilter-persistent net-tools openssl gnupg gnupg2 lsb-release cmake git screen socat xz-utils apt-transport-https dnsutils cron bash-completion ntpdate chrony jq openvpn easy-rsa python-is-python3"
local skip=""
for pkg in $COMMON_PKGS; do
apt-get install "${APT_ARGS[@]}" "$pkg" >/dev/null 2>&1 || skip="$skip $pkg"
done
[[ -n "$skip" ]] && echo -e "${Y} Paket tidak tersedia di OS ini, dilewati:${NC}$skip"
print_success "Packet Yang Dibutuhkan"
}
clear

function install_speedtest_ookla() {
clear
print_install "Menginstall Speedtest by Ookla"
export DEBIAN_FRONTEND=noninteractive
apt-get remove --purge "${APT_ARGS[@]}" speedtest-cli >/dev/null 2>&1 || true
apt-get install "${APT_ARGS[@]}" curl ca-certificates gnupg apt-transport-https >/dev/null 2>&1 || true
if ! /usr/bin/speedtest --version 2>&1 | grep -qi "Ookla"; then
curl -fsSL packagecloud.io -o /tmp/ookla-speedtest-install.sh >/dev/null 2>&1 && 
bash /tmp/ookla-speedtest-install.sh >/dev/null 2>&1 || true
apt-get update -y >/dev/null 2>&1 || true
apt-get install "${APT_ARGS[@]}" speedtest >/dev/null 2>&1 || true
fi
if /usr/bin/speedtest --version 2>&1 | grep -qi "Ookla"; then
print_success "Speedtest by Ookla"
else
echo -e "${Y} Speedtest by Ookla belum terpasang. Menu speedtest akan mencoba memasang ulang saat dipilih.${NC}"
sleep 2
fi
}
clear

restart_system(){
clear
domain=$(cat /etc/xray/domain 2>/dev/null || true)
echo -e "${OK} Instalasi selesai untuk domain: ${domain}"
}

password_default(){
return 0
}
clear

function pasang_ssl() {
clear
print_install "Memasang SSL Pada Domain"
rm -rf /etc/xray/xray.key
rm -rf /etc/xray/xray.crt
domain=$(cat /root/domain)
STOPWEBSERVER=$(lsof -i:80 | cut -d' ' -f1 | awk 'NR==2 {print $1}')
rm -rf /root/.acme.sh
mkdir /root/.acme.sh
systemctl stop $STOPWEBSERVER >/dev/null 2>&1 || true
systemctl stop nginx >/dev/null 2>&1 || true
curl netlify.app -o /root/.acme.sh/acme.sh
chmod +x /root/.acme.sh/acme.sh
/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
/root/.acme.sh/acme.sh --issue -d $domain --standalone -k ec-256
~/.acme.sh/acme.sh --installcert -d $domain --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --ecc || true
if [[ ! -s /etc/xray/xray.crt || ! -s /etc/xray/xray.key ]]; then
echo -e "${Y}SSL Let's Encrypt gagal/tertunda, membuat self-signed certificate sementara.${NC}"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -days 3650 -subj "/CN=$domain" >/dev/null 2>&1 || openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/xray/xray.key -out /etc/xray/xray.crt -days 3650 -subj "/CN=$domain" >/dev/null 2>&1
fi
chmod 777 /etc/xray/xray.key
print_success "SSL Certificate"
}

function make_folder_xray() {
rm -rf /etc/vmess/.vmess.db
rm -rf /etc/vless/.vless.db
rm -rf /etc/trojan/.trojan.db
rm -rf /etc/shadowsocks/.shadowsocks.db
rm -rf /etc/ssh/.ssh.db
rm -rf /etc/user-create/user.log
mkdir -p /etc/xray /etc/vmess /etc/vless /etc/trojan /etc/shadowsocks /etc/ssh
mkdir -p /usr/bin/xray/ /var/log/xray/ /var/www/html
mkdir -p /etc/kyt/limit/vmess/ip /etc/kyt/limit/vless/ip /etc/kyt/limit/trojan/ip /etc/kyt/limit/ssh/ip
mkdir -p /etc/limit/vmess /etc/limit/vless /etc/limit/trojan /etc/limit/ssh /etc/user-create
chmod +x /var/log/xray
touch /etc/xray/domain /var/log/xray/access.log /var/log/xray/error.log
touch /etc/vmess/.vmess.db /etc/vless/.vless.db /etc/trojan/.trojan.db /etc/shadowsocks/.shadowsocks.db /etc/ssh/.ssh.db
echo "& plughin Account" >>/etc/vmess/.vmess.db
echo "& plughin Account" >>/etc/vless/.vless.db
echo "& plughin Account" >>/etc/trojan/.trojan.db
echo "& plughin Account"
>>/etc/shadowsocks/.shadowsocks.db
echo "& plughin Account" >>/etc/ssh/.ssh.db
echo "echo -e 'Vps Config User Account'" >> /etc/user-create/user.log
}
haproxy_cfg_file() {
local v maj
v=$(haproxy -v 2>/dev/null | head -n1 | awk '{print $3}')
maj="${v%%.*}"
if [[ "$maj" =~ ^[0-9]+$ ]] && [ "$maj" -lt 2 ]; then
echo "media/haproxy-1.8.cfg"
else
echo "media/haproxy.cfg"
fi
}

function install_xray() {
clear
print_install "Core Xray Latest Version"
domainSock_dir="/run/xray"; ! [ -d $domainSock_dir ] && mkdir $domainSock_dir
chown www-data.www-data $domainSock_dir

latest_version="$(curl -fsSL github.com 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/."([^"]+)"./\1/')"
[[ -z "$latest_version" ]] && latest_version="v26.11.9"
bash -c "$(curl -L github.com)" @ install --version "$latest_version" --without-geodata
systemctl stop xray xray.service xray@.service >/dev/null 2>&1 || true
systemctl disable xray xray.service xray@.service >/dev/null 2>&1 || true

mkdir -p /usr/local/share/xray
wget -q -O /usr/local/share/xray/geosite.dat "github.com" >/dev/null 2>&1 || true
wget -q -O /usr/local/share/xray/geoip.dat "github.com" >/dev/null 2>&1 || true

chmod 755 /usr/local/bin/xray 2>/dev/null || true
chmod -R a+rX /usr/local/share/xray 2>/dev/null || true
mkdir -p /var/log/xray
touch /var/log/xray/access.log /var/log/xray/error.log
chown -R www-data.www-data /var/log/xray 2>/dev/null || true

fetch_file "media/config.json" "/etc/xray/config.json" >/dev/null 2>&1
fetch_file "media/runn.service" "/etc/systemd/system/runn.service" >/dev/null 2>&1
domain=$(cat /etc/xray/domain)
IPVS=$(cat /etc/xray/ipvps)
print_success "Core Xray Latest Version"

clear
curl -s ipinfo.io/city >>/etc/xray/city
curl -s ipinfo.io/org | cut -d " " -f 2-10 >>/etc/xray/isp
print_install "Memasang Konfigurasi Packet"
fetch_file "$(haproxy_cfg_file)" "/etc/haproxy/haproxy.cfg" >/dev/null 2>&1
fetch_file "media/xray.conf" "/etc/nginx/conf.d/xray.conf" >/dev/null 2>&1
fetch_file "media/nginx.conf" "/etc/nginx/nginx.conf"

# FIX 1: Ganti domain, perbaiki typo 'locatio', dan tambahkan route OVPNWS di port 1010
sed -i "s/xxx/${domain}/g" /etc/haproxy/haproxy.cfg
sed -i "s/alpn h2,http/1.1/alpn http/1.1,h2/g" /etc/haproxy/haproxy.cfg
sed -i "s/xxx/${domain}/g" /etc/nginx/conf.d/xray.conf
sed -i "s/locatio /location /g" /etc/nginx/conf.d/xray.conf

python3 - << 'PYEOF'
with open("/etc/nginx/conf.d/xray.conf", "r") as f:
content = f.read()
if "location ~ ^/(ovpn|openvpn)" not in content:
target = " location / {\n proxy_http_version 1.1;\n proxy_redirect off;\n proxy_pass http://127.0.0.1:10015;"
ovpn_block = """ location ~ ^/(ovpn|openvpn) {
proxy_http_version 1.1;
proxy_redirect off;
proxy_pass http://127.0.0.1:10012;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $http_x_forwarded_for;
proxy_set_header X-Forwarded-For $http_x_forwarded_for;
}
""" + target
content = content.replace(target, ovpn_block, 1)
with open("/etc/nginx/conf.d/xray.conf", "w") as f:
f.write(content)
PYEOF

cat /etc/xray/xray.crt /etc/xray/xray.key | tee /etc/haproxy/hap.pem >/dev/null
chmod +x /etc/systemd/system/runn.service

rm -rf /etc/systemd/system/xray.service.d
cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
print_success "Konfigurasi Packet"
}

function ssh(){
clear
print_install "Memasang Password SSH"
fetch_file "media/password" "/etc/pam.d/common-password"
chmod +x /etc/pam.d/common-password

DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/altgr select The default for the keyboard layout"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/compose select No compose key"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/ctrl_alt_bksp boolean false"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/layoutcode string de"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/layout select English"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/modelcode string pc105"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/model select Generic 105-key (Intl) PC"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/optionscode string "
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/store_defaults_in_debconf_db boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/switch select No temporary switch"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/toggle select No toggling"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_config_layout boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_config_options boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_layout boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_options boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/variantcode string "
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/variant select English"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/xkb-keymap select "

cd
cat > /etc/systemd/system/rc-local.service <<-END
[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
[Install]
WantedBy=multi-user.target
END

cat > /etc/rc.local <<-END
#!/bin/sh -e
exit 0
END

chmod +x /etc/rc.local
systemctl enable rc-local
systemctl start rc-local.service

echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

ln -fs /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
sed -i 's/AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config
print_success "Password SSH"
}

function udp_mini(){
clear
print_install "Memasang Service Limit IP & Quota"
fetch_file "media/limmit" "./limmit" && chmod +x limmit && ./limmit
fetch_file "media/udp-custom.sh" "./udp-custom.sh" && chmod +x udp-custom.sh && ./udp-custom.sh

mkdir -p /usr/local/kyt/
fetch_file "media/udp-mini" "/usr/local/kyt/udp-mini"
chmod +x /usr/local/kyt/udp-mini
fetch_file "media/udp-mini-1.service" "/etc/systemd/system/udp-mini-1.service"
fetch_file "media/udp-mini-2.service" "/etc/systemd/system/udp-mini-2.service"
fetch_file "media/udp-mini-3.service" "/etc/systemd/system/udp-mini-3.service"
for n in 1 2 3; do
systemctl disable udp-mini-$n
systemctl stop udp-mini-$n
systemctl enable udp-mini-$n
systemctl start udp-mini-$n
done
print_success "Limit IP Service"
}

function ssh_slow(){
clear
print_install "Memasang modul SlowDNS Server"
if systemctl is-active --quiet systemd-resolved 2>/dev/null || [ -f /etc/systemd/resolved.conf ]; then
mkdir -p /etc/systemd/resolved.conf.d/
cat >/etc/systemd/resolved.conf.d/noslowdnsconflict.conf <<'EOF'
[Resolve]
DNSStubListener=no
EOF
sed -i 's/^#?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || true
systemctl restart systemd-resolved >/dev/null 2>&1 || true
fi
fetch_file "slowdns/nameserver" "/tmp/nameserver" >/dev/null 2>&1
chmod +x /tmp/nameserver
bash /tmp/nameserver | tee /root/install.log
print_success "SlowDNS"
}

clear
function ins_SSHD(){
clear
print_install "Memasang SSHD"
fetch_file "media/sshd" "/etc/ssh/sshd_config" >/dev/null 2>&1
chmod 700 /etc/ssh/sshd_config
/etc/init.d/ssh restart
systemctl restart ssh
/etc/init.d/ssh status
print_success "SSHD"
}

clear
function ins_dropbear(){
clear
print_install "Menginstall Dropbear"
apt-get install "${APT_ARGS[@]}" dropbear > /dev/null 2>&1
fetch_file "media/issue.net" "/etc/issue.net"
fetch_file "media/dropbear.conf" "/etc/default/dropbear"
chmod +x /etc/default/dropbear
/etc/init.d/dropbear restart
/etc/init.d/dropbear status
print_success "Dropbear"
}

clear
function ins_vnstat(){
clear
print_install "Menginstall Vnstat"
apt-get install "${APT_ARGS[@]}" vnstat libsqlite3-dev > /dev/null 2>&1 || true
if ! command -v vnstat >/dev/null 2>&1; then
    wget -q https://humdi.net -O /tmp/vnstat.tar.gz \
    && tar zxf /tmp/vnstat.tar.gz -C /tmp \
    && (cd /tmp/vnstat-* && ./configure --prefix=/usr --sysconfdir=/etc && make && make install)
    rm -rf /tmp/vnstat.tar.gz /tmp/vnstat-*
fi
/etc/init.d/vnstat restart >/dev/null 2>&1 || true
vnstat -u -i $NET
sed -i 's/Interface "'""eth0""'"/Interface "'""$NET""'"/g' /etc/vnstat.conf
chown vnstat:vnstat /var/lib/vnstat -R
systemctl enable vnstat
/etc/init.d/vnstat restart
/etc/init.d/vnstat status
rm -f /root/vnstat-2.6.tar.gz
rm -rf /root/vnstat-2.6
print_success "Vnstat"
}

function ins_openvpn(){
clear
print_install "Menginstall OpenVPN"
run_file "media/openvpn"
/etc/init.d/openvpn restart
print_success "OpenVPN"
}

function ins_backup(){
clear
print_install "Memasang Backup Server"
apt-get install "${APT_ARGS[@]}" rclone msmtp-mta ca-certificates bsd-mailx >/dev/null 2>&1 || true
mkdir -p /root/.config/rclone
printf "q\n" | rclone config >/dev/null 2>&1 || true
cat >/etc/msmtprc <<'EOF'

Konfigurasi email backup dinonaktifkan secara default.

EOF
chmod 600 /etc/msmtprc
fetch_file "media/ipserver" "/etc/ipserver" && bash /etc/ipserver || true
print_success "Backup Server"
}

clear
function ins_swab(){
clear
print_install "Memasang Swap 1 G"
gotop_latest="$(curl -s github.com | grep tag_name | sed -E 's/."v(.)".*/\1/' | head -n 1)"
gotop_link="github.com"$gotop_latest"_linux_amd64.deb"
curl -sL "$gotop_link" -o /tmp/gotop.deb
dpkg -i /tmp/gotop.deb >/dev/null 2>&1

dd if=/dev/zero of=/swapfile bs=1024 count=1048576
mkswap /swapfile
chown root:root /swapfile
chmod 0600 /swapfile >/dev/null 2>&1
swapon /swapfile >/dev/null 2>&1
sed -i '$ i/swapfile swap swap defaults 0 0' /etc/fstab

chronyd -q 'server 0.id.pool.ntp.org iburst'
chronyc sourcestats -v
chronyc tracking -v

run_file "media/bbr.sh" || true
print_success "Swap 1 G"
}


FIX 2: Ganti ws-epro (yang deadlock) dengan Python WebSocket Bridge untuk SSHWS (10015) & OVPNWS (10012)
# FIX 2: Ganti ws-epro (yang deadlock) dengan Python WebSocket Bridge untuk SSHWS (10015) & OVPNWS (10012)

function ins_epro(){
clear
print_install "Memasang WebSocket Proxy (SSHWS & OVPNWS)"
fetch_file "media/tun.conf" "/usr/bin/tun.conf" >/dev/null 2>&1 || true

cat << 'PYEOF' > /usr/local/bin/ws-ssh.py
#!/usr/bin/env python3
import socket, threading, select

LISTENING_ADDR = '127.0.0.1'
LISTENING_PORT = 10015
TARGET_HOST = '127.0.0.1'
TARGET_PORT = 109
RESPONSE = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"

def handle_client(client_sock):
    try:
        request = client_sock.recv(4096)
        if not request:
            client_sock.close()
            return
        target_sock = socket.create_connection((TARGET_HOST, TARGET_PORT))
        client_sock.sendall(RESPONSE)
        sockets = [client_sock, target_sock]
        while True:
            r, _, _ = select.select(sockets, [], [], 60)
            if not r:
                break
            for s in r:
                data = s.recv(8192)
                if not data:
                    return
                if s is client_sock:
                    target_sock.sendall(data)
                else:
                    client_sock.sendall(data)
    except Exception:
        pass
    finally:
        client_sock.close()

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind((LISTENING_ADDR, LISTENING_PORT))
server.listen(128)
while True:
    conn, _ = server.accept()
    threading.Thread(target=handle_client, args=(conn,), daemon=True).start()
PYEOF

sed -e 's/10015/10012/g' -e 's/109/1194/g' /usr/local/bin/ws-ssh.py > /usr/local/bin/ws-ovpn.py
chmod +x /usr/local/bin/ws-ssh.py /usr/local/bin/ws-ovpn.py

cat << 'SVCEOF' > /etc/systemd/system/ws.service
[Unit]
Description=WebSocket SSH & OpenVPN Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c '/usr/bin/python3 /usr/local/bin/ws-ssh.py & /usr/bin/python3 /usr/local/bin/ws-ovpn.py & wait'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable ws
systemctl restart ws

fetch_file "media/ftvpn" "/usr/sbin/ftvpn" >/dev/null 2>&1
chmod +x /usr/sbin/ftvpn

# Memblokir trafik BitTorrent dan peer-to-peer menggunakan aturan iptables
for str in "get_peers" "announce_peer" "find_node" "BitTorrent" "BitTorrent protocol" "peer_id=" ".torrent" "announce.php?passkey=" "torrent" "announce" "info_hash"; do
    iptables -A FORWARD -m string --string "$str" --algo bm -j DROP
done

iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload
}





