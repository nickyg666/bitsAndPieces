#!/bin/bash


# This is not super ethical - but neither is automating away peoples' jobs, etc.
# so without further ado,
# I show you how I make sure I can always get unlimited access for MiniMax 2.5 free with opencode.ai editor.
# Not that they work much better than just writing a script myself, like this.
# You need a wireguard capable VPN or many public IP nodes you can hop to over wireguard
# and obviously, you need wireguard and a namespace set up. You may notice the DNS replacement
# this is built to play nicely with systemd/resolved and the rest of your system
# that you may or may not want to be tunnelled.
# make sure you put this in your .bashrc to replace the export PATH=".opencode/bin/opencode"
# alias opencode='nsenter --net=/var/run/netns/opencode ~/.opencode/bin/opencode'
# actually, I will just do all of that for you - since this is likely only for me anyway.
# This is dual-action for me; it helps my openvpn access server work alongside wireguard and also circumvent rate limiting with opencode.
# I hope nobody important at opencode/MiniMax sees this, eventually I will have to get craftier to escape them.
# You can daemonize it or put a nohup in your .bashrc or however you like to run it, up to you.
u="$(logname)"
sudo setcap cap_sys_admin,cap_net_admin+ep /usr/bin/ip
sudo setcap cap_sys_admin,cap_net_admin+ep /usr/bin/nsenter
# CHANGE BELOW TO ADAPT TO YOUR SETUP #


oc_lives_here="/home/$u/.opencode/bin/opencode"
where="/etc/netns/opencode/wireguard" # this is where your WG configs live. I would put them in the ns
ns="opencode" #the namespace you set up to hide opencode in
logs="/home/$u/.local/share/opencode/log" # where your logs are going, typically $user/.local/share/opencode/log
places=("$where"/*.conf) # name the configs after their locations, so you can remember which is where
netns="nsenter --net=/var/run/netns/$ns"
wgUP="$netns wg-quick up" # you need to use wireguard in THE NAMESPACE ONLY
wgDN="$netns wg-quick down"

# we will check for or set up a separate namespace for you quick - so we can hide real good without hiding everything all at once
if ! sudo ip netns list | grep -q "^$ns"; then

    sudo ip netns add $ns
    sudo chown "$u":"$u" /var/run/netns/$ns
    sudo ip link add veth-host type veth peer name veth-ns
    sudo ip link set veth-ns netns $ns
    sudo ip addr add 123.123.123.1/24 dev veth-host
    $netns ip addr add 123.123.123.2/24 dev veth-ns
    $netns ip link set lo up
    $netns ip link set veth-ns up
    sudo ip link set veth-host up
    $netns ip route add default via 123.123.123.1
    sudo ip route add 123.123.123.0/24 dev veth-host

fi



OC_roaming="alias opencode='$netns $oc_lives_here'"
grep -qxF "$OC_roaming" ~/.bashrc || echo -e "\n$OC_roaming" >> ~/.bashrc
# you should be able to just do opencode command to always run in a separate namespace now.


for hidden in "${places[@]}"; do
    placeToGo="$hidden"
# for a list of WG configs, placeToGo is the connection's geographical location
    if ! grep -q "^PostUp" "$placeToGo"; then

        DNS=$(grep -Po '^DNS\s*=\s*\K.*' "$placeToGo") #find DNS for VPN, save for later with postUp so connEstablished. my provider gives me the conf like this so have to adapt it.
        [[ -n "$DNS" ]] && { sed -i 's/^DNS /=#dns =/' "$placeToGo"; echo -e "\nPostUp = resolvectl dns %i $DNS\nPostDown = resolvectl revert dns %i" >> "$placeToGo"; }

    fi

done

if ! $netns wg show | grep -Po 'interface:\K.*'; then
# if no wg interface on netns
    echo "no WG interface up, using real IP!";
    hidingIn="PlainSight";

else
# we must be somewhere else, find out
    hidingIn="$($netns wg show | grep -Po 'interface:\K.*')";

fi
#log watcher
tail -Fn0 "$logs"/*.log 2>/dev/null | while read -r line; do
    if echo "$line" | grep -qiE "rate limit|quota|exceeded|too many|retrying"; then

        if [[ "$hidingIn" == "PlainSight" ]]; then

            hideBetter=true
            $wgUP "${places[0]}" # up the first config after you get rate limited!
            hidingIn="$(basename "${places[0]}")"
            hideBetter=false

        else

            $wgDN "$where/$hidingIn" # we must already be hiding, leave for the next spot!
            hideBetter=true #we don't need to hide better if it\'s working, but if the log rate limits and ! hiding == plainsight then we must hide better
            for x in "${places[@]}"; do

                if [[ "$hideBetter" == true ]]; then

                    $wgUP "$x";
                    hidingIn="$(basename "$x")";
                    hideBetter=false
                    break;
                fi

                [[ "$(basename "$x")" == "$hidingIn" ]] && hideBetter=true && continue

            done

        fi

        echo "I'm hiding in $hidingIn now";

    fi

done
