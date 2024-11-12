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

# Konfigrasi IP Statis Untuk Internal Network
cat <<EOF | sudo tee /etc/netplan/00-installer-config.yaml
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
sudo netplan apply

# Restart DHCP Server
sudo /etc/init.d/isc-dhcp-server restart 

# Mengaktifkan IP Forwarding Dan Mengonfigurasi IPTables
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Menyimpan Aturan IPTables
sudo netfilter-persistent save
