#!/bin/bash
set -e

# Menambah Repositori Kartolo
cat <<EOF | sudo tee /etc/apt/sources.list
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-updates main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-security main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-backports main restricted universe multiverse
deb http://kartolo.sby.datautama.net.id/ubuntu/ focal-proposed main restricted universe multiverse
EOF

# Update Repositori
sudo apt update

# Install Isc-Dhcp-Server, IPTables, Dan Iptables-Persistent
sudo apt install sshpass
sudo apt install -y isc-dhcp-server iptables iptables-persistent

# Konfigurasi DHCP
cat <<EOF | sudo tee /etc/dhcp/dhcpd.conf
subnet 192.168.24.0 netmask 255.255.255.0 {
    range 192.168.24.10 192.168.24.100;
    option routers 192.168.24.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOF

# Konfigurasi Interfaces DHCP
sudo sed -i 's/^INTERFACESv4=.*/INTERFACESv4="eth1.10"/' /etc/default/isc-dhcp-server

# Konfigrasi IP Statis Untuk Internal Network menggunakan Netplan
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

# Terapkan Konfigurasi Netplan dan Aktifkan Interface
echo "Mengaktifkan interface jaringan..."
sudo ip link set eth1 up
sudo netplan apply

# Restart DHCP Server
echo "Merestart DHCP server..."
sudo systemctl restart isc-dhcp-server

# Mengaktifkan IP Forwarding Dan Mengonfigurasi IPTables
echo "Mengonfigurasi IP Forwarding dan IPTables..."
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Menyimpan Aturan IPTables
sudo netfilter-persistent save

# Konfigurasi Routing untuk jaringan MikroTik
echo "Menambahkan konfigurasi routing..."
sudo ip route add 192.168.200.0/24 via 192.168.200.1 || echo "Gagal menambahkan route. Pastikan jaringan MikroTik aktif."

# 4. Konfigurasi Cisco Switch melalui SSH dengan username dan password root
echo "Mengonfigurasi Cisco Switch..."
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

# 5. Konfigurasi MikroTik melalui SSH tanpa prompt
echo "Mengonfigurasi MikroTik..."
if [ -z "" ]; then
    ssh -o StrictHostKeyChecking=no admin@192.168.200.1 <<EOF
interface vlan add name=vlan10 vlan-id=10 interface=ether1
ip address add address=192.168.24.1/24 interface=vlan10      # Sesuaikan dengan IP di VLAN Ubuntu
ip address add address=192.168.200.1/24 interface=ether2     # IP address MikroTik di network lain
ip route add dst-address=192.168.24.0/24 gateway=192.168.24.1
EOF
else
    sshpass -p "" ssh -o StrictHostKeyChecking=no admin@192.168.200.1 <<EOF
interface vlan add name=vlan10 vlan-id=10 interface=ether1
ip address add address=192.168.24.1/24 interface=vlan10      # Sesuaikan dengan IP di VLAN Ubuntu
ip address add address=192.168.200.1/24 interface=ether2     # IP address MikroTik di network lain
ip route add dst-address=192.168.24.0/24 gateway=192.168.24.1
EOF
fi

echo "Otomasi konfigurasi selesai."
