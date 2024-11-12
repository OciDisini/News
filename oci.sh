#!/bin/bash

# Variabel Konfigurasi
VLAN_INTERFACE="eth1.10"
VLAN_ID=10
IP_ADDR="192.168.24.1/24"      # IP address untuk interface VLAN di Ubuntu
DHCP_CONF="/etc/dhcp/dhcpd.conf"
SWITCH_IP="192.168.24.35"       # IP Cisco Switch yang diperbarui
MIKROTIK_IP="192.168.200.1"     # IP MikroTik yang baru
USER_SWITCH="root"              # Username SSH untuk Cisco Switch
USER_MIKROTIK="admin"           # Username SSH default MikroTik
PASSWORD_SWITCH="root"          # Password untuk Cisco Switch
PASSWORD_MIKROTIK=""            # Kosongkan jika MikroTik tidak memiliki password

set -e

# Menambah Repositori Kartolo
cat <<EOF | sudo tee /etc/apt/sources.list
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-updates main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-security main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-backports main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-proposed main restricted universe multiverse
EOF

sudo apt update
sudo apt install sshpass -y
sudo apt install -y isc-dhcp-server iptables iptables-persistent

# 1. Konfigurasi VLAN di Ubuntu Server
echo "Mengonfigurasi VLAN di Ubuntu Server..."
ip link add link eth1 name $VLAN_INTERFACE type vlan id $VLAN_ID
ip addr add $IP_ADDR dev $VLAN_INTERFACE
ip link set up dev $VLAN_INTERFACE

# 2. Konfigurasi DHCP Server
echo "Menyiapkan konfigurasi DHCP server..."
cat <<EOL | sudo tee $DHCP_CONF
# Konfigurasi subnet untuk VLAN 10
subnet 192.168.24.0 netmask 255.255.255.0 {
    range 192.168.24.10 192.168.24.100;
    option routers 192.168.24.1;
    option subnet-mask 255.255.255.0;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
    option domain-name "example.local";
}
EOL

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

# Restart DHCP server untuk menerapkan konfigurasi baru
echo "Restarting DHCP server..."
sudo systemctl restart isc-dhcp-server

# 3. Konfigurasi Routing di Ubuntu Server
echo "Menambahkan konfigurasi routing..."
ip route add 192.168.200.0/24 via $MIKROTIK_IP

# 4. Konfigurasi Cisco Switch melalui SSH dengan username dan password root
echo "Mengonfigurasi Cisco Switch..."
sshpass -p "$PASSWORD_SWITCH" ssh -o StrictHostKeyChecking=no $USER_SWITCH@$SWITCH_IP <<EOF
enable
configure terminal
vlan $VLAN_ID
name VLAN10
exit
interface e0/1
switchport mode access
switchport access vlan $VLAN_ID
exit
end
write memory
EOF

# 5. Konfigurasi MikroTik melalui SSH tanpa prompt
echo "Mengonfigurasi MikroTik..."
if [ -z "$PASSWORD_MIKROTIK" ]; then
    ssh -o StrictHostKeyChecking=no $USER_MIKROTIK@$MIKROTIK_IP <<EOF
interface vlan add name=vlan10 vlan-id=$VLAN_ID interface=ether1
ip address add address=192.168.24.1/24 interface=vlan10      # Sesuaikan dengan IP di VLAN Ubuntu
ip address add address=192.168.200.1/24 interface=ether2     # IP address MikroTik di network lain
ip route add dst-address=192.168.24.0/24 gateway=192.168.24.1
EOF
else
    sshpass -p "$PASSWORD_MIKROTIK" ssh -o StrictHostKeyChecking=no $USER_MIKROTIK@$MIKROTIK_IP <<EOF
interface vlan add name=vlan10 vlan-id=$VLAN_ID interface=ether1
ip address add address=192.168.24.1/24 interface=vlan10      # Sesuaikan dengan IP di VLAN Ubuntu
ip address add address=192.168.200.1/24 interface=ether2     # IP address MikroTik di network lain
ip route add dst-address=192.168.24.0/24 gateway=192.168.24.1
EOF
fi

echo "Otomasi konfigurasi selesai."
