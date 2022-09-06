#!/bin/bash

set +x
set -e

echo "INTERNAL_PORT=${INTERNAL_PORT:=9701}"
echo "CLI_PORT=${CLI_PORT:=9702}"
echo "CHAIN=${CHAIN:=DOCKER-USER}"
echo "MAX_CONN=${MAX_CONN:=500}"

usage() {
  echo
  echo "Usage:"
  echo -n "INTERFACE=[your_network_interface] IP_FILE=[path_to_ip_addresses_file, defaults to first argument, env wins ties] "
  echo -n "INTERNAL_PORT=[indy port, default 9701] CLI_PORT=[client port, default 9702] CHAIN=[iptables chain to edit, default DOCKER-USER]"
  echo "$0 [IP_FILE]"
  echo
  echo "This script will add rules to your ip tables chain CHAIN to allow incoming connections on port INTERNAL_PORT"
  echo "only from ips listed in the IP_FILE. It will also restrict the number of connections to port CLI_PORT to MAX_CONN."
  echo
  echo "The ip adresses file should contain the list of nodes"
  echo "in your network. One ip address per line."
  echo "The network interface should be the physical one used for incoming connections from the internet"
  echo
  echo "This script needs to be run as root/via sudo."
  echo
}

# skip existing rules to avoid duplicates
add_new_rule() {
  RULE="$@"

  if iptables -C $RULE 2>/dev/null 1>&2; then
    echo "[skip] $RULE already exists"
  elif [[ "$RULE" == *"DROP"* ]] || [[ "$RULE" == *"RETURN"* ]]; then
    iptables -A $RULE
    echo "[ok] $RULE added to the end of the chain"
  else
    iptables -I $RULE
    echo "[ok] $RULE added to the beginning of the chain"
  fi
}

make_last_rule() {
  RULE="$@"
  while iptables -C $RULE 2>/dev/null 1>&2; do
    iptables -D $RULE
    echo "[ok] $RULE deleted"
  done
  iptables -A $RULE
  echo "[ok] $RULE added to the end of the chain"
}

echo "INTERFACE=${INTERFACE:=ens18}"

# check if INTERFACE is set to an inet facing interface
if ! ip a | grep inet | grep "$INTERFACE" >/dev/null; then
  echo "[ERROR] interface '$INTERFACE' does not seem to be an internet facing interface"
  usage
  exit 1
fi

echo "IP_FILE=${IP_FILE:=$1}"

if ! [ -f "$IP_FILE" ]; then
  echo "[ERROR] file '$IP_FILE' not found"
  usage
  exit 1
fi


# -h --help --whatever
if ! [ -z "$2" ]; then
  usage
  exit 0
fi

# 9701 whitelist approach: drop all others INCOMING (-i) connections
add_new_rule $CHAIN -p tcp -i $INTERFACE --dport $INTERNAL_PORT -j DROP

# 9701 create IP whitelist from file
while read IP; do
  if [[ "$IP" != "#"* ]] && [[ "$IP" != "" ]]; then
    add_new_rule $CHAIN -p tcp --dport $INTERNAL_PORT -s $IP -j ACCEPT
  fi
done <"$IP_FILE"

# make sure, RETURN ist the last rule
make_last_rule $CHAIN -j RETURN

# 9702 connlimit
# add_new_rule $CHAIN -p tcp --syn --dport $CLI_PORT -m connlimit --connlimit-above $MAX_CONN -j REJECT
echo "Connection limit are no longer set via this script. There is now a seperate script to handle connection limits."
echo "See ./add_ddos_protection_iptables_rule.sh -h"
