#!/bin/bash
# Written by Steven Tierney on 20-Mar-2022
# This script will auto-generate Wireguard Configurations for names device(s)
# Here the Router of the LAN is used as the endpoint. This, alongside DDNS and Port Forwarding, works for me.
# Meant for use in the 'bash' shell, this script will..
# - Create a folder for the new device (within /etc/wireguard)
# - Generate a public/private key pair for the new device
# - Generate a Private Shared Key for the new device
# - Make a Config for the new device
# - Create a QR Code image for the new device 
#
# Reprequisites
# - Wireguard to be installed, and Interface created, with public & private key files available
# - qrencode package to be installed (to create the QR Code images of the device configurations)
# - Port forwarding set up on LAN Internet Router (e.g. Router Port 50000 > Wireguard Server Port 50000)
# - Dynamic DNS created to track the Internet IP of the Internet Router
#
# Hat tip to folks at OpenWRT who provided the basis for this script.
# https://openwrt.org/docs/guide-user/services/vpn/wireguard/automated

############################################
# Change these to suit what needs to be done
############################################

# New devices to add
# Set StartAt to start at somewhere other than user_1
# Set Quantity, then add the user_X per peer
# Example: If startat=3 and quantity=1, user_3 will be used by the script
#
# The number of devices to create
export quantity="1"
# The device to start at
export startat="1"

# List of devices / users
export user_1="alpha"
export user_2="bravo"
export user_3="charlie"
export user_4="delta"
export user_5="echo"
export user_6="foxtrot"
export user_7="golf"
export user_8="hotel"

# Variables of Wireguard Network
# Wireguard network prefix
export WG_PREFIX="10.10.10"
# Wireguard server address on the wireguard network
export WG_SERVER_IP="${WG_PREFIX}.1/24"
# DNS Server for Wireguard clients to use
export WG_DNSSERVER="8.8.8.8"
# Dynamic DNS for Wireguard clients
export WG_DDNS="my.ddns-domain.org"
# Port on Internet Router
export WG_PORT="50000"
# Wireguard network server configiration file
export WG_NETWORK="wg0"
# Wireguard network server public key file
export WG_PUBKEY_FILE="/etc/wireguard/publickey"

# Variables of LAN
# Internal network
export INTERNAL_NETWORK="192.168.0.0/24"
# LAN address of internet router
export INTERNET_ROUTER="192.168.0.1"

############################################
# Don't change anything below here
############################################

# Script variables
export WG_PEERS_DIR="/etc/wireguard/${WG_NETWORK}_peers"
export allusers=(${user_1} ${user_2} ${user_3} ${user_4} ${user_5} ${user_6} ${user_7} ${user_8})

# Functions
function last_peer_ID () {
	cd "${WG_PEERS_DIR}"
	ls | sort -V | tail -1 | cut -d '_' -f 1
	cd
}

function last_peer_IP () {
	cd "${WG_PEERS_DIR}"
	if [ "$(ls -A $WG_PEERS_DIR)" ]; then
		# awk '/Address/' $peer_ID*/*.conf | cut -d '.' -f 3 | tr -d /32
		awk '/Address/' $(last_peer_ID)*/*.conf | cut -d '.' -f 4 | cut -d'/' -f1
	fi
  	cd
}

############################################
# Main Block
############################################

# Create a folder for the devices
mkdir -p "${WG_PEERS_DIR}"

# Get the next Peer ID number, and the next PEER_IP address number
export peer_ID=$(last_peer_ID) ; export peer_ID=$((peer_ID+1))
export peer_IP=$(last_peer_IP) ; export peer_IP=$((peer_IP+1))

# Correct for if there are no peers
if [ "$peer_IP" -eq "1" ]; then
	export peer_IP=$((peer_IP+1))
fi


# Take down the interface
echo "Stopping WireGuard interface... "
#wg-quick down ${WG_NETWORK}
systemctl stop wg-quick@${WG_NETWORK}

# Begin the creation
n=$((${startat}-1))
m=$((${n}+${quantity}))

# Loop
while [ "$n" -lt "$m" ] ;
do
	username="${allusers[$n]}"

	# Configure Variables
	echo ""
	echo "Defining variables for '${peer_ID}_${username}'... "

	# Create directory for storing peers
	export peer_NAME="${peer_ID}_${username}"
	export peer_DIR="${WG_PEERS_DIR}/${peer_NAME}"
	echo "Creating directory for peer '${peer_NAME}'... "
	mkdir -p "${peer_DIR}"

	# Generate peer keys
	echo "Generating peer keys for '${peer_NAME}'... "
	wg genkey | tee "${peer_DIR}/${peer_NAME}_private.key" | wg pubkey | tee "${peer_DIR}/${peer_NAME}_public.key" >/dev/null 2>&1

	# Generate Pre-shared key
	echo  "Generating peer PSK for '${peer_NAME}'... "
	wg genpsk | tee "${peer_DIR}/${peer_NAME}.psk" >/dev/null 2>&1

	# Back up the server file
	cp -p "/etc/wireguard/${WG_NETWORK}.conf" "/etc/wireguard/${WG_NETWORK}.conf.$(date '+%Y%m%d_%H%M%S').${peer_NAME}"

	# Add peer to Wireguard server file
	cat <<-EOF >> "/etc/wireguard/${WG_NETWORK}.conf"

[Peer]
PublicKey = $(cat ${peer_DIR}/${peer_NAME}_public.key)
PresharedKey = $(cat ${peer_DIR}/${peer_NAME}.psk)
AllowedIPs = ${WG_PREFIX}.${peer_IP}/32
Endpoint = ${INTERNET_ROUTER}:${WG_PORT}
EOF

	# Create peer configuration
	echo "Creating config for '${peer_NAME}'... "
	# [Interface] - Peer's Private Key
	# [Peer] - Server's public key
	cat <<-EOF > "${peer_DIR}/${peer_NAME}.conf"
[Interface]
Address = ${WG_PREFIX}.${peer_IP}/32
PrivateKey = $(cat ${peer_DIR}/${peer_NAME}_private.key)
DNS = ${WG_DNSSERVER}

[Peer]
PublicKey = $(cat ${WG_PUBKEY_FILE})
PresharedKey = $(cat ${peer_DIR}/${peer_NAME}.psk)
PersistentKeepalive = 25
AllowedIPs = 0.0.0.0/0, ${INTERNAL_NETWORK}, ::/0
Endpoint = ${WG_DDNS}:${WG_PORT}
EOF

	/usr/bin/qrencode -t SVG -r "${peer_DIR}/${peer_NAME}.conf" -o "${peer_DIR}/${peer_NAME}.svg"
	echo "Completed config for '${peer_NAME}'"

	# Increment variables by '1'
	peer_ID=$((peer_ID+1))
	peer_IP=$((peer_IP+1))
	n=$((n+1))

	if [ "$n" -eq "$m" ]; then
		break
	fi
done


# Restart WireGuard interface
echo "Restarting WireGuard interface... "
#wg-quick up ${WG_NETWORK}
systemctl start wg-quick@${WG_NETWORK}
echo "Done"

# Restart firewall
#echo -en "\nRestarting firewall... "
#/etc/init.d/firewall restart >/dev/null 2>&1
#echo "Done"
