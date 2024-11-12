#!/bin/bash
set -e

# Definisi warna
BIRU='\033[1;34m'
HIJAU='\033[1;32m'
MERAH='\033[1;31m'
NC='\033[0m' # No Color

# Menambah Repositori Kartolo
echo -e "${BIRU}Menambahkan repositori Kartolo...${NC}"
cat <<EOF | sudo tee /etc/apt/sources.list
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-updates main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-security main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-backports main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-proposed main restricted universe multiverse
EOF

# Update Repositori
echo -e "${BIRU}Memperbarui repositori...${NC}"
sudo apt update

# Install Paket yang Diperlukan
echo -e "${BIRU}Menginstal paket yang diperlukan...${NC}"
sudo apt install -y sshpass isc-dhcp-server iptables iptables-persistent

# Konfigurasi DHCP
echo -e "${BIRU}Mengonfigurasi DHCP...${NC}"
cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet 192.168.24.0 netmask 255.255.255.0 {
    range 192.168.24.10 192.168.24.100;
    option routers 192.168.24.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOF

# Konfigurasi Interfaces DHCP
echo -e "${BIRU}Mengonfigurasi interface DHCP...${NC}"
sudo sed -i 's/^INTERFACESv4=.*/INTERFACESv4="eth1.10"/' /etc/default/isc-dhcp-server

# Konfigurasi IP Statis untuk Internal Network
echo -e "${BIRU}Mengonfigurasi IP statis untuk jaringan internal...${NC}"
cat <<EOF | sudo tee /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
    eth1:
      dhcp4: no
  vlans:
    eth1.10:
      id: 10
      link: eth1
      addresses: [192.168.24.1/24]
EOF

# Terapkan Konfigurasi Netplan
echo -e "${BIRU}Menerapkan konfigurasi Netplan...${NC}"
sudo netplan apply
sleep 5

# Restart DHCP Server
echo -e "${BIRU}Merestart server DHCP...${NC}"
sudo systemctl restart isc-dhcp-server

# Mengaktifkan IP Forwarding dan Konfigurasi IPTables
echo -e "${BIRU}Mengaktifkan IP forwarding dan konfigurasi IPTables...${NC}"
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Menyimpan Aturan IPTables
echo -e "${BIRU}Menyimpan aturan IPTables...${NC}"
sudo netfilter-persistent save

# Periksa koneksi ke Cisco Switch sebelum konfigurasi
echo -e "${BIRU}Memeriksa koneksi ke switch Cisco di 192.168.24.35...${NC}"
if ping -c 3 192.168.24.35 > /dev/null; then
    echo -e "${HIJAU}Koneksi ke switch Cisco berhasil. Melanjutkan konfigurasi switch...${NC}"
    
    # Konfigurasi Cisco Switch melalui SSH
    sshpass -p "root" ssh -o StrictHostKeyChecking=no root@192.168.24.35 <<EOF
enable
configure terminal
vlan 10
name VLAN10
exit
interface e0/1
switchport mode access
switchport access vlan 10
exit
end
write memory
EOF
else
    echo -e "${MERAH}Gagal terhubung ke switch Cisco di 192.168.24.35. Periksa konfigurasi jaringan.${NC}"
    exit 1
fi

# Konfigurasi MikroTik melalui SSH
echo -e "${BIRU}Memeriksa koneksi ke MikroTik di 192.168.200.1...${NC}"
if ping -c 3 192.168.200.1 > /dev/null; then
    echo -e "${HIJAU}Koneksi ke MikroTik berhasil. Melanjutkan konfigurasi MikroTik...${NC}"
    
    sshpass -p "admin" ssh -o StrictHostKeyChecking=no admin@192.168.200.1 <<EOF
interface vlan add name=vlan10 vlan-id=10 interface=ether1
ip address add address=192.168.24.1/24 interface=vlan10
ip address add address=192.168.200.1/24 interface=ether2
ip route add dst-address=192.168.24.0/24 gateway=192.168.24.1
EOF
else
    echo -e "${MERAH}Gagal terhubung ke MikroTik di 192.168.200.1. Periksa konfigurasi jaringan.${NC}"
    exit 1
fi

echo -e "${HIJAU}Otomasi konfigurasi selesai.${NC}"
