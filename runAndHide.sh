#!/bin/bash
# I'm like really mad right now that I keep getting passed over for jobs. Maybe I need to start NOT telling them what I need in an employer/workplace.
set +x
# You can background it or put a nohup in your .bashrc or however you like to run it, up to you.
# CHANGE BELOW TO ADAPT TO YOUR SETUP #
u="$(logname)"
HOME=/home/$u
    # if not ipv4_forwarding enabled, then do it
if ! [[ $(cat /proc/sys/net/ipv4/ip_forward) == 1 ]]; then
    sudo sysctl -w net.ipv4.ip_forward=1;
fi

shopt -s nullglob # make sure globbing works the way we need it to in order to expand paths correctly
ns="vpn-jail" #the namespace you set up to hide opencode in
netns=(sudo ip netns exec "$ns")
oc_inst_dir="$HOME/.opencode/bin/opencode"
logs="$HOME/.local/share/opencode/log" # where your logs are going, typically $user/.local/share/opencode/log
cfgs="/etc/wireguard" # this is where your WG configs live. I would put them in the ns
ns_dir="/etc/netns/$ns"
# Inside namespace
"${netns[@]}" ip route replace default via 123.123.123.1

### FIND THE INTERFACE THAT'S GOOD FOR GETTING TO THE INTERNET - DO IT DYNAMICALLY IN CASE WE CHANGE DEV MACHINES
iface=$(sudo ip route show default | awk '{print $5}' | head -n 1)

### VETH SETUP - TO MAKE IMAGINARY ETHERNET CABLE FOR NAMESPACE v = virtual ethernet
# On host
sudo iptables -t nat -A POSTROUTING -s 123.123.2/24 -o $iface -j MASQUERADE
sudo iptables -A FORWARD -i v-host -j ACCEPT
sudo iptables -A FORWARD -o v-host -j ACCEPT

v_net="123.123.123.0/24" # this is the new subnet the host -> namespace virtual ethernet cable will use
v_host="123.123.123.1" # this is manipulated from the host only - to connect the namespace to networks.
v_ns="123.123.123.2" # this is the lan IP of opencode's new namespace
if ! [[ -f /etc/netns/$ns/resolv.conf ]]; then
    echo "nameserver 1.1.1.1" | sudo tee /etc/netns/$ns/resolv.conf >/dev/null
fi


# we will check for or set up a separate namespace for you quick - so we can hide real good without hiding everything all at once
if ! sudo ip netns list | grep -q "^$ns"; then
    #setup namespace for vlan sorta thing, add generic cloudflare resolver so we can wg-quick up or only do wg after rate limit on real IP
    sudo mkdir -p /etc/netns/$ns
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
fi

### FIX OPENCODE TO RUN IN THIS NAMESPACE AS THE USER
if ! grep -q "^alias opencode=" "$HOME/.bashrc"; then

    OC_roaming="alias opencode='${netns[@]} sudo -u $u $oc_inst_dir'"
    echo -e "\n$OC_roaming" >> "$HOME/.bashrc"
# you should be able to just do opencode command to always run in a separate namespace now.
fi

where=("$cfgs"/*.conf)
if [[ ${#where[@]} -eq 0 ]]; then
    echo "We didn't find any wireguard stuff in your $cfgs dir, get them from your VPN provider for each location, or design your own by creating other peers at other public IPs.";
    exit 2;
fi

echo "places to run away to: "${where[@]}""
in_safehouse="no"
echo "go to "${where[0]}"!"

now=0
run_away() {
    # Cycle to the next WireGuard config
    where_to_go="${where[$((now % ${#where[@]}))]}"
    ((now++))

    echo "Running away to $where_to_go"

    # If interface exists, bring it down first
    wgif=$(basename "$where_to_go" .conf)
    if "${netns[@]}" wg show interfaces | grep -qw "$wgif"; then
        echo "Bringing down existing $wgif"
        "${netns[@]}" wg-quick down "$wgif"
    fi

    # Bring up WireGuard in the namespace
    "${netns[@]}" wg-quick up "$where_to_go"

    # Grab the DNS from wg-quick (it pushes DNS automatically)
    if [[ -f "$where_to_go" ]]; then
        wg_dns=$(grep -i "^DNS" "$where_to_go" | cut -d= -f2 | tr -d ' ')
        if [[ -n "$wg_dns" ]]; then
            echo "nameserver $wg_dns" | sudo tee /etc/netns/$ns/resolv.conf >/dev/null
            echo "Namespace DNS updated to $wg_dns"
        fi
    fi

    in_safehouse="yes"
    echo "Now safely in $wgif"
}
if [[ "$in_safehouse" == "no" ]]; then
    run_away
else
# we must be somewhere else, find out
    echo "We're already in $where_to_go. We will run away and grab a new IP when rate limit is detected."
fi

tail -Fn0 "$logs"/*.log 2>/dev/null | while read -r line; do

    if [[ "$line" =~ rate|free|exceeded|retrying|credit|remain|refill ]]; then

        run_away
#leave, lay in wait for next event, give user 5 mins to retry request, else run away forever
        sleep 300
    fi

done
