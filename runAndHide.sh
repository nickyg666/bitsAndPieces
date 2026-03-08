#!/bin/bash
# if you know, you know. This is something I am using to make my work more productive. It is a bitsAndPieces production.
# CHANGE BELOW TO ADAPT TO YOUR SETUP #
u="$(logname)"

    # if not ipv4_forwarding enabled, then do it
if ! [[ $(cat /proc/sys/net/ipv4/ip_forward) == 1 ]]; then
    sudo sysctl -w net.ipv4.ip_forward=1;
fi

shopt -s nullglob # make sure globbing works the way we need it to in order to expand paths correctly
ns="opencode" #the namespace you set up to hide opencode in
oc_inst_dir="$HOME/.opencode/bin/opencode"
logs="$HOME/.local/share/opencode/log" # where your logs are going, typically $user/.local/share/opencode/log
cfgs="/etc/wireguard" # this is where your WG configs live. I would put them in the ns
where=("$cfgs"/*.conf)
[[ ${#where[@]} -eq 0 ]] && { echo "We didn't find any wireguard stuff in your $cfgs dir, get them from your VPN provider for each location, or design your own by creating other peers at other public IPs."; exit 1; }

### FIND THE INTERFACE THAT'S GOOD FOR GETTING TO THE INTERNET - DO IT DYNAMICALLY IN CASE WE CHANGE DEV MACHINES
# why would I need the fifth result? it's actually the fifth space separated thing, like an array. fifth word of default route should be the interface. I need to learn awk better - did you know thats a whole language?
iface=$(sudo ip route show default | awk '{print $5}' | head -n 1)

### VETH SETUP - TO MAKE IMAGINARY ETHERNET CABLE FOR NAMESPACE v = virtual ethernet

v_net="123.123.123.0/24" # this is the new subnet the host -> namespace virtual ethernet cable will use
v_host="123.123.123.1" # this is manipulated from the host only - to connect the namespace to networks.
v_ns="123.123.123.2" # this is the lan IP of opencode's new namespace
### aliasing for the long command to execute something in the namespace
netns=(sudo ip netns exec "$ns")
whereami=("${netns[@]}" wg show interfaces)


# we will check for or set up a separate namespace for you quick - so we can hide real good without hiding everything all at once
if ! sudo ip netns list | grep -q "^$ns"; then
    #setup namespace for vlan sorta thing, add generic cloudflare resolver so we can wg-quick up or only do wg after rate limit on real IP
    sudo mkdir -p /etc/netns/$ns
    echo "nameserver 1.1.1.1" | sudo tee /etc/netns/$ns/resolv.conf >/dev/null
    sudo ip netns add $ns;
    # we need to establish a link with two interfaces - one on the host that will go to the namespace, and another for the namespace
    sudo ip link add v-host type veth peer name v-ns;
    sudo ip link set v-ns netns $ns;

### HOST IP ASSIGNMENT / UP THE IFACE
    sudo ip addr add "$v_host/24" dev v-host
    sudo ip link set v-host up
### SETUP THE NAMESPACE SIDE OF THE NETWORK
    "${netns[@]}" ip addr add "$v_ns/24" dev v-ns
    "${netns[@]}" ip link set lo up
    "${netns[@]}" ip link set v-ns up

    #add default route + enable ipv4 forward if not /TABLES so we can go places
    "${netns[@]}" ip route add default via "$v_host"
    # FIXED TO DYNAMICALLY RESOLVE ADAPTER NAME
    sudo iptables -t nat -C POSTROUTING -s "$v_net" -o "$iface" -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -s "$v_net" -o "$iface" -j MASQUERADE
    sudo iptables -A FORWARD -i v-host -j ACCEPT
    sudo iptables -A FORWARD -o v-host -j ACCEPT
fi
### now let's set up wireguard so we can run and hide the instance
run_to="hidingSpots"

if ! "${netns[@]}" ip link show "$run_to" &>/dev/null; then
    sudo ip link add "$run_to" type wireguard
    sudo ip link set "$run_to" netns "$ns"
    "${netns[@]}" ip link set "$run_to" up
fi


### FIX OPENCODE TO RUN IN THIS NAMESPACE AS THE USER
if ! grep -q "^alias opencode=" "$HOME/.bashrc"; then

    OC_roaming="alias opencode='${netns[@]} sudo -u $u $oc_inst_dir'"
    echo -e "\n$OC_roaming" >> "$HOME/.bashrc"
# you should be able to just do opencode command to always run in a separate namespace now.
fi

if ! "${whereami[@]}" | grep -q .; then
# if no wg interface on netns
    echo "no WG interface up, using real IP!";
    hidingIn="PlainSight";

else
# we must be somewhere else, find out
    echo "We're already telling opencode/namespace we are in a place";
    echo "We will run and hide when rate limit is detected."
fi

now=0
run_away() {

    where_to_go="${where[$now]}"
    echo "Running away to $(basename "$where_to_go")"
    "${netns[@]}" wg setconf "$run_to" "$where_to_go"
    "${netns[@]}" ip route replace default dev "$run_to"
    ((now++))
    ((now%=${#where[@]}))
}

#log watcher
loc=0
chill=5

tail -Fn0 "$logs"/*.log 2>/dev/null | while read -r line; do

    if [[ "$line" =~ rate\ limit|quota|exceeded|too\ many|retrying ]]; then

        ima="$(date +%s)"
        (( ima - loc < chill )) && continue
        loc=$ima
        run_away

    fi

done
