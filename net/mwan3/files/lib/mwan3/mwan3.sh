#!/bin/sh

. /usr/share/libubox/jshn.sh

IP4="ip -4"
IP6="ip -6"
IPS="ipset"
IPT4="iptables -t mangle -w"
IPT6="ip6tables -t mangle -w"
IPT4R="iptables-restore -T mangle -w -n"
IPT6R="ip6tables-restore -T mangle -w -n"
CONNTRACK_FILE="/proc/net/nf_conntrack"
IPv6_REGEX="([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,7}:|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|"
IPv6_REGEX="${IPv6_REGEX}[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|"
IPv6_REGEX="${IPv6_REGEX}:((:[0-9a-fA-F]{1,4}){1,7}|:)|"
IPv6_REGEX="${IPv6_REGEX}fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|"
IPv6_REGEX="${IPv6_REGEX}::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|"
IPv6_REGEX="${IPv6_REGEX}([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])"

MWAN3_STATUS_DIR="/var/run/mwan3"
MWAN3_INTERFACE_MAX=""
DEFAULT_LOWEST_METRIC=256
MMX_MASK=""
MMX_DEFAULT=""
MMX_BLACKHOLE=""
MM_BLACKHOLE=""

MMX_UNREACHABLE=""
MM_UNREACHABLE=""

command -v ip6tables > /dev/null
NO_IPV6=$?

mwan3_push_update()
{
	# helper function to build an update string to pass on to
	# IPTR or IPS RESTORE. Modifies the 'update' variable in
	# the local scope.
	update="$update
$*";
}

mwan3_update_dev_to_table()
{
	local _tid
	# shellcheck disable=SC2034
	mwan3_dev_tbl_ipv4=" "
	# shellcheck disable=SC2034
	mwan3_dev_tbl_ipv6=" "

	update_table()
	{
		local family curr_table device enabled
		let _tid++
		config_get family "$1" family ipv4
		network_get_device device "$1"
		[ -z "$device" ] && return
		config_get enabled "$1" enabled
		[ "$enabled" -eq 0 ] && return
		curr_table=$(eval "echo	 \"\$mwan3_dev_tbl_${family}\"")
		export "mwan3_dev_tbl_$family=${curr_table}${device}=$_tid "
	}
	network_flush_cache
	config_foreach update_table interface
}

mwan3_update_iface_to_table()
{
	local _tid
	mwan3_iface_tbl=" "
	update_table()
	{
		let _tid++
		export mwan3_iface_tbl="${mwan3_iface_tbl}${1}=$_tid "
	}
	config_foreach update_table interface
}

mwan3_get_true_iface()
{
	local family V
	_true_iface=$2
	config_get family "$iface" family ipv4
	if [ "$family" = "ipv4" ]; then
		V=4
	elif [ "$family" = "ipv6" ]; then
		V=6
	fi
	ubus call "network.interface.${iface}_${V}" status &>/dev/null && _true_iface="${iface}_${V}"
	export "$1=$_true_iface"
}

mwan3_route_line_dev()
{
	# must have mwan3 config already loaded
	# arg 1 is route device
	local _tid route_line route_device route_family entry curr_table
	route_line=$2
	route_family=$3
	route_device=$(echo "$route_line" | sed -ne "s/.*dev \([^ ]*\).*/\1/p")
	unset "$1"
	[ -z "$route_device" ] && return

	curr_table=$(eval "echo	 \"\$mwan3_dev_tbl_${route_family}\"")
	for entry in $curr_table; do
		if [ "${entry%%=*}" = "$route_device" ]; then
			_tid=${entry##*=}
			export "$1=$_tid"
			return
		fi
	done
}

# counts how many bits are set to 1
# n&(n-1) clears the lowest bit set to 1
mwan3_count_one_bits()
{
	local count n
	count=0
	n=$(($1))
	while [ "$n" -gt "0" ]; do
		n=$((n&(n-1)))
		count=$((count+1))
	done
	echo $count
}

# maps the 1st parameter so it only uses the bits allowed by the bitmask (2nd parameter)
# which means spreading the bits of the 1st parameter to only use the bits that are set to 1 in the 2nd parameter
# 0 0 0 0 0 1 0 1 (0x05) 1st parameter
# 1 0 1 0 1 0 1 0 (0xAA) 2nd parameter
#     1   0   1          result
mwan3_id2mask()
{
	local bit_msk bit_val result
	bit_val=0
	result=0
	for bit_msk in $(seq 0 31); do
		if [ $((($2>>bit_msk)&1)) = "1" ]; then
			if [ $((($1>>bit_val)&1)) = "1" ]; then
				result=$((result|(1<<bit_msk)))
			fi
			bit_val=$((bit_val+1))
		fi
	done
	printf "0x%x" $result
}

mwan3_init()
{
	local bitcnt
	local mmdefault

	[ -d $MWAN3_STATUS_DIR ] || mkdir -p $MWAN3_STATUS_DIR/iface_state

	# mwan3's MARKing mask (at least 3 bits should be set)
	if [ -e "${MWAN3_STATUS_DIR}/mmx_mask" ]; then
		MMX_MASK=$(cat "${MWAN3_STATUS_DIR}/mmx_mask")
		MWAN3_INTERFACE_MAX=$(uci_get_state mwan3 globals iface_max)
	else
		config_load mwan3
		config_get MMX_MASK globals mmx_mask '0x3F00'
		echo "$MMX_MASK"| tr 'A-F' 'a-f' > "${MWAN3_STATUS_DIR}/mmx_mask"
		LOG debug "Using firewall mask ${MMX_MASK}"

		bitcnt=$(mwan3_count_one_bits MMX_MASK)
		mmdefault=$(((1<<bitcnt)-1))
		MWAN3_INTERFACE_MAX=$((mmdefault-3))
		uci_toggle_state mwan3 globals iface_max "$MWAN3_INTERFACE_MAX"
		LOG debug "Max interface count is ${MWAN3_INTERFACE_MAX}"
	fi

	# mark mask constants
	bitcnt=$(mwan3_count_one_bits MMX_MASK)
	mmdefault=$(((1<<bitcnt)-1))
	MM_BLACKHOLE=$((mmdefault-2))
	MM_UNREACHABLE=$((mmdefault-1))

	# MMX_DEFAULT should equal MMX_MASK
	MMX_DEFAULT=$(mwan3_id2mask mmdefault MMX_MASK)
	MMX_BLACKHOLE=$(mwan3_id2mask MM_BLACKHOLE MMX_MASK)
	MMX_UNREACHABLE=$(mwan3_id2mask MM_UNREACHABLE MMX_MASK)
}

mwan3_lock() {
	lock /var/run/mwan3.lock
	#LOG debug "$1 $2 (lock)"
}

mwan3_unlock() {
	#LOG debug "$1 $2 (unlock)"
	lock -u /var/run/mwan3.lock
}

mwan3_get_src_ip()
{
	local family _src_ip true_iface
	true_iface=$2
	unset "$1"
	config_get family "$true_iface" family ipv4
	if [ "$family" = "ipv4" ]; then
		network_get_ipaddr _src_ip "$true_iface"
		[ -n "$_src_ip" ] || _src_ip="0.0.0.0"
	elif [ "$family" = "ipv6" ]; then
		network_get_ipaddr6 _src_ip "$true_iface"
		[ -n "$_src_ip" ] || _src_ip="::"
	fi
	export "$1=$_src_ip"
}

mwan3_get_iface_id()
{
	local _tmp
	[ -z "$mwan3_iface_tbl" ] && mwan3_update_iface_to_table
	_tmp="${mwan3_iface_tbl##* ${2}=}"
	_tmp=${_tmp%% *}
	export "$1=$_tmp"
}

mwan3_set_custom_ipset_v4()
{
	local custom_network_v4

	for custom_network_v4 in $($IP4 route list table "$1" | awk '{print $1}' | grep -E '[0-9]{1,3}(\.[0-9]{1,3}){3}'); do
		LOG notice "Adding network $custom_network_v4 from table $1 to mwan3_custom_v4 ipset"
		mwan3_push_update -! add mwan3_custom_v4 "$custom_network_v4"
	done
}

mwan3_set_custom_ipset_v6()
{
	local custom_network_v6

	for custom_network_v6 in $($IP6 route list table "$1" | awk '{print $1}' | grep -E "$IPv6_REGEX"); do
		LOG notice "Adding network $custom_network_v6 from table $1 to mwan3_custom_v6 ipset"
		mwan3_push_update -! add mwan3_custom_v6 "$custom_network_v6"
	done
}

mwan3_set_custom_ipset()
{
	local update=""

	mwan3_push_update -! create mwan3_custom_v4 hash:net
	config_list_foreach "globals" "rt_table_lookup" mwan3_set_custom_ipset_v4

	mwan3_push_update -! create mwan3_custom_v6 hash:net family inet6
	config_list_foreach "globals" "rt_table_lookup" mwan3_set_custom_ipset_v6

	mwan3_push_update -! create mwan3_connected list:set
	mwan3_push_update -! add mwan3_connected mwan3_custom_v4
	mwan3_push_update -! add mwan3_connected mwan3_custom_v6
	error=$(echo "$update" | $IPS restore 2>&1) || LOG error "set_custom_ipset: $error"
}


mwan3_set_connected_ipv4()
{
	local connected_network_v4 candidate_list cidr_list
	local ipv4regex='[0-9]{1,3}(\.[0-9]{1,3}){3}'
	$IPS -! create mwan3_connected_v4 hash:net
	$IPS create mwan3_connected_v4_temp hash:net

	candidate_list=""
	cidr_list=""
	route_lists()
	{
		$IP4 route | awk '{print $1}'
		$IP4 route list table 0 | awk '{print $2}'
	}
	for connected_network_v4 in $(route_lists | grep -E "$ipv4regex"); do
		if [ -z "${connected_network_v4##*/*}" ]; then
			cidr_list="$cidr_list $connected_network_v4"
		else
			candidate_list="$candidate_list $connected_network_v4"
		fi
	done

	for connected_network_v4 in $cidr_list; do
		$IPS -! add mwan3_connected_v4_temp "$connected_network_v4"
	done
	for connected_network_v4 in $candidate_list; do
		ipset -q test mwan3_connected_v4_temp "$connected_network_v4" ||
			$IPS -! add mwan3_connected_v4_temp "$connected_network_v4"
	done

	$IPS add mwan3_connected_v4_temp 224.0.0.0/3

	$IPS swap mwan3_connected_v4_temp mwan3_connected_v4
	$IPS destroy mwan3_connected_v4_temp

}

mwan3_set_connected_iptables()
{
	local connected_network_v6 source_network_v6 error
	local update=""
	mwan3_set_connected_ipv4

	[ $NO_IPV6 -eq 0 ] && {
		mwan3_push_update -! create mwan3_connected_v6 hash:net family inet6
		mwan3_push_update flush mwan3_connected_v6

		for connected_network_v6 in $($IP6 route | awk '{print $1}' | grep -E "$IPv6_REGEX"); do
			mwan3_push_update -! add mwan3_connected_v6 "$connected_network_v6"
		done

		mwan3_push_update -! create mwan3_source_v6 hash:net family inet6
		for source_network_v6 in $($IP6 addr ls | sed -ne 's/ *inet6 \([^ \/]*\).* scope global.*/\1/p'); do
			mwan3_push_update -! add mwan3_source_v6 "$source_network_v6"
		done
	}

	mwan3_push_update -! create mwan3_connected list:set
	mwan3_push_update flush mwan3_connected
	mwan3_push_update -! add mwan3_connected mwan3_connected_v4
	[ $NO_IPV6 -eq 0 ] && mwan3_push_update -! add mwan3_connected mwan3_connected_v6

	mwan3_push_update -! create mwan3_dynamic_v4 hash:net
	mwan3_push_update -! add mwan3_connected mwan3_dynamic_v4

	[ $NO_IPV6 -eq 0 ] && mwan3_push_update -! create mwan3_dynamic_v6 hash:net family inet6
	[ $NO_IPV6 -eq 0 ] && mwan3_push_update -! add mwan3_connected mwan3_dynamic_v6
	error=$(echo "$update" | $IPS restore 2>&1) || LOG error "set_connected_iptables: $error"
}

mwan3_set_general_rules()
{
	local IP

	for IP in "$IP4" "$IP6"; do
		[ "$IP" = "$IP6" ] && [ $NO_IPV6 -ne 0 ] && continue
		RULE_NO=$((MM_BLACKHOLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_BLACKHOLE/$MMX_MASK blackhole
		fi

		RULE_NO=$((MM_UNREACHABLE+2000))
		if [ -z "$($IP rule list | awk -v var="$RULE_NO:" '$1 == var')" ]; then
			$IP rule add pref $RULE_NO fwmark $MMX_UNREACHABLE/$MMX_MASK unreachable
		fi
	done
}

mwan3_set_general_iptables()
{
	local IPT current update error
	for IPT in "$IPT4" "$IPT6"; do
		[ "$IPT" = "$IPT6" ] && [ $NO_IPV6 -ne 0 ] && continue
		current="$($IPT -S)"
		update="*mangle"
		if [ -n "${current##*-N mwan3_ifaces_in*}" ]; then
			mwan3_push_update -N mwan3_ifaces_in
		fi

		if [ -n "${current##*-N mwan3_connected*}" ]; then
			mwan3_push_update -N mwan3_connected
			$IPS -! create mwan3_connected list:set
			mwan3_push_update -A mwan3_connected \
					  -m set --match-set mwan3_connected dst \
					  -j MARK --set-xmark $MMX_DEFAULT/$MMX_MASK
		fi

		if [ -n "${current##*-N mwan3_rules*}" ]; then
			mwan3_push_update -N mwan3_rules
		fi

		if [ -n "${current##*-N mwan3_hook*}" ]; then
			mwan3_push_update -N mwan3_hook
			# do not mangle ipv6 ra service
			if [ "$IPT" = "$IPT6" ]; then
				mwan3_push_update -A mwan3_hook \
						  -p ipv6-icmp \
						  -m icmp6 --icmpv6-type 133 \
						  -j RETURN
				mwan3_push_update -A mwan3_hook \
						  -p ipv6-icmp \
						  -m icmp6 --icmpv6-type 134 \
						  -j RETURN
				mwan3_push_update -A mwan3_hook \
						  -p ipv6-icmp \
						  -m icmp6 --icmpv6-type 135 \
						  -j RETURN
				mwan3_push_update -A mwan3_hook \
						  -p ipv6-icmp \
						  -m icmp6 --icmpv6-type 136 \
						  -j RETURN
				mwan3_push_update -A mwan3_hook \
						  -p ipv6-icmp \
						  -m icmp6 --icmpv6-type 137 \
						  -j RETURN
				# do not mangle outgoing echo request
				mwan3_push_update -A mwan3_hook \
						  -m set --match-set mwan3_source_v6 src \
						  -p ipv6-icmp \
						  -m icmp6 --icmpv6-type 128 \
						  -j RETURN

			fi
			mwan3_push_update -A mwan3_hook \
					  -j CONNMARK --restore-mark --nfmask "$MMX_MASK" --ctmask "$MMX_MASK"
			mwan3_push_update -A mwan3_hook \
					  -m mark --mark 0x0/$MMX_MASK \
					  -j mwan3_ifaces_in
			mwan3_push_update -A mwan3_hook \
					  -m mark --mark 0x0/$MMX_MASK \
					  -j mwan3_connected
			mwan3_push_update -A mwan3_hook \
					  -m mark --mark 0x0/$MMX_MASK \
					  -j mwan3_rules
			mwan3_push_update -A mwan3_hook \
					  -j CONNMARK --save-mark --nfmask "$MMX_MASK" --ctmask "$MMX_MASK"
			mwan3_push_update -A mwan3_hook \
					  -m mark ! --mark $MMX_DEFAULT/$MMX_MASK \
					  -j mwan3_connected
		fi

		if [ -n "${current##*-A PREROUTING -j mwan3_hook*}" ]; then
			mwan3_push_update -A PREROUTING -j mwan3_hook
		fi
		if [ -n "${current##*-A OUTPUT -j mwan3_hook*}" ]; then
			mwan3_push_update -A OUTPUT -j mwan3_hook
		fi
		mwan3_push_update COMMIT
		mwan3_push_update ""
		if [ "$IPT" = "$IPT4" ]; then
			error=$(echo "$update" | $IPT4R 2>&1) || LOG error "set_general_iptables: $error"
		else
			error=$(echo "$update" | $IPT6R 2>&1) || LOG error "set_general_iptables: $error"
		fi
	done
}

mwan3_create_iface_iptables()
{
	local id family connected_name IPT IPTR current update error

	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		connected_name=mwan3_connected
		IPT="$IPT4"
		IPTR="$IPT4R"
		$IPS -! create $connected_name list:set

	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ]; then
		connected_name=mwan3_connected_v6
		IPT="$IPT6"
		IPTR="$IPT6R"
		$IPS -! create $connected_name hash:net family inet6
	else
		return
	fi
	current="$($IPT -S)"
	update="*mangle"
	if [ -n "${current##*-N mwan3_ifaces_in*}" ]; then
		mwan3_push_update -N mwan3_ifaces_in
	fi

	if [ -n "${current##*-N mwan3_iface_in_$1*}" ]; then
		mwan3_push_update -N "mwan3_iface_in_$1"
	else
		mwan3_push_update -F "mwan3_iface_in_$1"
	fi

	mwan3_push_update -A "mwan3_iface_in_$1" \
			  -i "$2" \
			  -m set --match-set $connected_name src \
			  -m mark --mark "0x0/$MMX_MASK" \
			  -m comment --comment "default" \
			  -j MARK --set-xmark "$MMX_DEFAULT/$MMX_MASK"
	mwan3_push_update -A "mwan3_iface_in_$1" \
			  -i "$2" \
			  -m mark --mark "0x0/$MMX_MASK" \
			  -m comment --comment "$1" \
			  -j MARK --set-xmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK"

	if [ -n "${current##*-A mwan3_ifaces_in -m mark --mark 0x0/$MMX_MASK -j mwan3_iface_in_${1}*}" ]; then
		mwan3_push_update -A mwan3_ifaces_in \
				  -m mark --mark 0x0/$MMX_MASK \
				  -j "mwan3_iface_in_$1"
		LOG debug "create_iface_iptables: mwan3_iface_in_$1 not in iptables, adding"
	else
		LOG debug "create_iface_iptables: mwan3_iface_in_$1 already in iptables, skip"
	fi

	mwan3_push_update COMMIT
	mwan3_push_update ""
	error=$(echo "$update" | $IPTR 2>&1) || LOG error "create_iface_iptables: $error"

}

mwan3_delete_iface_iptables()
{
	local IPT
	config_get family "$1" family ipv4

	if [ "$family" = "ipv4" ]; then
		IPT="$IPT4"
	fi

	if [ "$family" = "ipv6" ]; then
		[ $NO_IPV6 -ne 0 ] && return
		IPT="$IPT6"
	fi

	$IPT -D mwan3_ifaces_in \
	     -m mark --mark 0x0/$MMX_MASK \
	     -j "mwan3_iface_in_$1" &> /dev/null
	$IPT -F "mwan3_iface_in_$1" &> /dev/null
	$IPT -X "mwan3_iface_in_$1" &> /dev/null

}

mwan3_create_iface_route()
{
	local id via metric V V_ IP family
	local iface device cmd true_iface

	iface=$1
	device=$2
	config_get family "$iface" family ipv4
	mwan3_get_iface_id id "$iface"

	[ -n "$id" ] || return 0

	mwan3_get_true_iface true_iface $iface
	if [ "$family" = "ipv4" ]; then
		V_=""
		IP="$IP4"
	elif [ "$family" = "ipv6" ]; then
		V_=6
		IP="$IP6"
	fi

	network_get_gateway${V_} via "$true_iface"

	{ [ -z "$via" ] || [ "$via" = "0.0.0.0" ] || [ "$via" = "::" ] ; } && unset via

	network_get_metric metric "$true_iface"

	$IP route flush table "$id"
	cmd="$IP route add table $id default \
	     ${via:+via} $via \
	     ${metric:+metric} $metric \
	     dev $2"
	$cmd || LOG warn "ip cmd failed $cmd"

}

mwan3_add_non_default_iface_route()
{
	local tid route_line family IP id
	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ]; then
		IP="$IP6"
	fi

	mwan3_update_dev_to_table
	$IP route list table main | grep -v "^default\|linkdown\|^::/0\|^fe80::/64\|^unreachable" | while read -r route_line; do
		mwan3_route_line_dev "tid" "$route_line" "$family"
		if [ -z "$tid" ] || [ "$tid" = "$id" ]; then
			$IP route add table $id $route_line ||
				LOG warn "failed to add $route_line to table $id"
		fi

	done
}

mwan3_add_all_nondefault_routes()
{
	local tid IP route_line ipv family active_tbls tid

	add_active_tbls()
	{
		let tid++
		config_get family "$1" family ipv4
		[ "$family" != "$ipv" ] && return
		$IP route list table $tid 2>/dev/null | grep -q "^default\|^::/0" && {
			active_tbls="$active_tbls${tid} "
		}
	}

	add_route()
	{
		let tid++
		[ -n "${active_tbls##* $tid *}" ] && return
		$IP route add table $tid $route_line ||
			LOG warn "failed to add $route_line to table $tid"
	}

	mwan3_update_dev_to_table
	for ipv in ipv4 ipv6; do
		[ "$ipv" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && continue
		if [ "$ipv" = "ipv4" ]; then
			IP="$IP4"
		elif [ "$ipv" = "ipv6" ]; then
			IP="$IP6"
		fi
		tid=0
		active_tbls=" "
		config_foreach add_active_tbls interface
		$IP route list table main | grep -v "^default\|linkdown\|^::/0\|^fe80::/64\|^unreachable" | while read -r route_line; do
			mwan3_route_line_dev "tid" "$route_line" "$ipv"
			if [ -n "$tid" ]; then
				$IP route add table $tid $route_line
			else
				config_foreach add_route interface
			fi
		done
	done
}
mwan3_delete_iface_route()
{
	local id

	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		$IP4 route flush table "$id"
	fi

	if [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ]; then
		$IP6 route flush table "$id"
	fi
}

mwan3_create_iface_rules()
{
	local id family IP

	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	while [ -n "$($IP rule list | awk '$1 == "'$((id+1000)):'"')" ]; do
		$IP rule del pref $((id+1000))
	done

	while [ -n "$($IP rule list | awk '$1 == "'$((id+2000)):'"')" ]; do
		$IP rule del pref $((id+2000))
	done

	$IP rule add pref $((id+1000)) iif "$2" lookup "$id"
	$IP rule add pref $((id+2000)) fwmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK" lookup "$id"
}

mwan3_delete_iface_rules()
{
	local id family IP

	config_get family "$1" family ipv4
	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ]; then
		IP="$IP6"
	else
		return
	fi

	while [ -n "$($IP rule list | awk '$1 == "'$((id+1000)):'"')" ]; do
		$IP rule del pref $((id+1000))
	done

	while [ -n "$($IP rule list | awk '$1 == "'$((id+2000)):'"')" ]; do
		$IP rule del pref $((id+2000))
	done
}

mwan3_delete_iface_ipset_entries()
{
	local id setname entry

	mwan3_get_iface_id id "$1"

	[ -n "$id" ] || return 0

	for setname in $(ipset -n list | grep ^mwan3_sticky_); do
		for entry in $(ipset list "$setname" | grep "$(mwan3_id2mask id MMX_MASK | awk '{ printf "0x%08x", $1; }')" | cut -d ' ' -f 1); do
			$IPS del "$setname" $entry
		done
	done
}

mwan3_rtmon()
{
	local protocol
	for protocol in "ipv4" "ipv6"; do
		pid="$(pgrep -f "mwan3rtmon $protocol")"
		[ "$protocol" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && continue
		if [ "${pid}" = "" ]; then
			[ -x /usr/sbin/mwan3rtmon ] && /usr/sbin/mwan3rtmon $protocol &
		fi
	done
}

mwan3_track()
{
	local track_ips pids

	mwan3_list_track_ips()
	{
		track_ips="$track_ips $1"
	}
	config_list_foreach "$1" track_ip mwan3_list_track_ips

	# don't match device in case it changed from last launch
	if pids=$(pgrep -f "mwan3track $1 "); then
		kill -TERM $pids > /dev/null 2>&1
		sleep 1
		kill -KILL $(pgrep -f "mwan3track $1 ") > /dev/null 2>&1
	fi

	if [ -n "$track_ips" ]; then
		[ -x /usr/sbin/mwan3track ] && MWAN3_STARTUP=0 /usr/sbin/mwan3track "$1" "$2" "$3" "$4" $track_ips &
	fi
}

mwan3_set_policy()
{
	local id iface family metric probability weight device is_lowest is_offline IPT IPTR total_weight current update error

	is_lowest=0
	config_get iface "$1" interface
	config_get metric "$1" metric 1
	config_get weight "$1" weight 1

	[ -n "$iface" ] || return 0
	network_get_device device "$iface"
	[ "$metric" -gt $DEFAULT_LOWEST_METRIC ] && LOG warn "Member interface $iface has >$DEFAULT_LOWEST_METRIC metric. Not appending to policy" && return 0

	mwan3_get_iface_id id "$iface"

	[ -n "$id" ] || return 0

	[ "$(mwan3_get_iface_hotplug_state "$iface")" = "online" ]
	is_offline=$?

	config_get family "$iface" family ipv4

	if [ "$family" = "ipv4" ]; then
		IPT="$IPT4"
		IPTR="$IPT4R"
	elif [ "$family" = "ipv6" ]; then
		IPT="$IPT6"
		IPTR="$IPT6R"
	fi
	current="$($IPT -S)"
	update="*mangle"

	if [ "$family" = "ipv4" ] && [ $is_offline -eq 0 ]; then
		if [ "$metric" -lt "$lowest_metric_v4" ]; then
			is_lowest=1
			total_weight_v4=$weight
			lowest_metric_v4=$metric
		elif [ "$metric" -eq "$lowest_metric_v4" ]; then
			total_weight_v4=$((total_weight_v4+weight))
			total_weight=$total_weight_v4
		else
			return
		fi
	elif [ "$family" = "ipv6" ] && [ $NO_IPV6 -eq 0 ] && [ $is_offline -eq 0 ]; then
		if [ "$metric" -lt "$lowest_metric_v6" ]; then
			is_lowest=1
			total_weight_v6=$weight
			lowest_metric_v6=$metric
		elif [ "$metric" -eq "$lowest_metric_v6" ]; then
			total_weight_v6=$((total_weight_v6+weight))
			total_weight=$total_weight_v6
		else
			return
		fi
	fi
	if [ $is_lowest -eq 1 ]; then
		mwan3_push_update -F "mwan3_policy_$policy"
		mwan3_push_update -A "mwan3_policy_$policy" \
				  -m mark --mark 0x0/$MMX_MASK \
				  -m comment --comment \"$iface $weight $weight\" \
				  -j MARK --set-xmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK"
	elif [ $is_offline -eq 0 ]; then
		probability=$((weight*1000/total_weight))
		if [ "$probability" -lt 10 ]; then
			probability="0.00$probability"
		elif [ $probability -lt 100 ]; then
			probability="0.0$probability"
		elif [ $probability -lt 1000 ]; then
			probability="0.$probability"
		else
			probability="1"
		fi

		mwan3_push_update -I "mwan3_policy_$policy" \
				  -m mark --mark 0x0/$MMX_MASK \
				  -m statistic \
				  --mode random \
				  --probability "$probability" \
				  -m comment --comment \"$iface $weight $total_weight\" \
				  -j MARK --set-xmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK"
	elif [ -n "$device" ]; then
		echo "$current" | grep -q "^-A mwan3_policy_$policy.*--comment .* [0-9]* [0-9]*" ||
			mwan3_push_update -I "mwan3_policy_$policy" \
					  -o "$device" \
					  -m mark --mark 0x0/$MMX_MASK \
					  -m comment --comment \"out $iface $device\" \
					  -j MARK --set-xmark $MMX_DEFAULT/$MMX_MASK
	fi
	mwan3_push_update COMMIT
	mwan3_push_update ""
	error=$(echo "$update" | $IPTR 2>&1) || LOG error "set_policy ($1): $error"

}

mwan3_create_policies_iptables()
{
	local last_resort lowest_metric_v4 lowest_metric_v6 total_weight_v4 total_weight_v6 policy IPT current update error

	policy="$1"

	config_get last_resort "$1" last_resort unreachable

	if [ "$1" != "$(echo "$1" | cut -c1-15)" ]; then
		LOG warn "Policy $1 exceeds max of 15 chars. Not setting policy" && return 0
	fi

	for IPT in "$IPT4" "$IPT6"; do
		[ "$IPT" = "$IPT6" ] && [ $NO_IPV6 -ne 0 ] && continue
		current="$($IPT -S)"
		update="*mangle"
		if [ -n "${current##*-N mwan3_policy_$1*}" ]; then
			mwan3_push_update -N "mwan3_policy_$1"
		fi

		mwan3_push_update -F "mwan3_policy_$1"

		case "$last_resort" in
			blackhole)
				mwan3_push_update -A "mwan3_policy_$1" \
						  -m mark --mark 0x0/$MMX_MASK \
						  -m comment --comment "blackhole" \
						  -j MARK --set-xmark $MMX_BLACKHOLE/$MMX_MASK
				;;
			default)
				mwan3_push_update -A "mwan3_policy_$1" \
						  -m mark --mark 0x0/$MMX_MASK \
						  -m comment --comment "default" \
						  -j MARK --set-xmark $MMX_DEFAULT/$MMX_MASK
				;;
			*)
				mwan3_push_update -A "mwan3_policy_$1" \
						  -m mark --mark 0x0/$MMX_MASK \
						  -m comment --comment "unreachable" \
						  -j MARK --set-xmark $MMX_UNREACHABLE/$MMX_MASK
				;;
		esac
		mwan3_push_update COMMIT
		mwan3_push_update ""
		if [ "$IPT" = "$IPT4" ]; then
			error=$(echo "$update" | $IPT4R 2>&1) || LOG error "create_policies_iptables ($1): $error"
		else
			error=$(echo "$update" | $IPT6R 2>&1) || LOG error "create_policies_iptables ($1): $error"
		fi
	done

	lowest_metric_v4=$DEFAULT_LOWEST_METRIC
	total_weight_v4=0

	lowest_metric_v6=$DEFAULT_LOWEST_METRIC
	total_weight_v6=0

	config_list_foreach "$1" use_member mwan3_set_policy
}

mwan3_set_policies_iptables()
{
	config_foreach mwan3_create_policies_iptables policy
}

mwan3_set_sticky_iptables()
{
	local id iface
	for iface in $(echo "$current" | grep "^-A $policy" | cut -s -d'"' -f2 | awk '{print $1}'); do
		if [ "$iface" = "$1" ]; then

			mwan3_get_iface_id id "$1"

			[ -n "$id" ] || return 0
			if [ -z "${current##*-N mwan3_iface_in_$1*}" ]; then
				mwan3_push_update -I "mwan3_rule_$rule" \
						  -m mark --mark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK" \
						  -m set ! --match-set "mwan3_sticky_$rule" src,src \
						  -j MARK --set-xmark "0x0/$MMX_MASK"
				mwan3_push_update -I "mwan3_rule_$rule" \
						  -m mark --mark "0/$MMX_MASK" \
						  -j MARK --set-xmark "$(mwan3_id2mask id MMX_MASK)/$MMX_MASK"
			fi
		fi
	done
}

mwan3_set_user_iptables_rule()
{
	local ipset family proto policy src_ip src_port src_iface src_dev
	local sticky dest_ip dest_port use_policy timeout policy
	local global_logging rule_logging loglevel rule_policy rule ipv

	rule="$1"
	ipv="$2"
	rule_policy=0
	config_get sticky "$1" sticky 0
	config_get timeout "$1" timeout 600
	config_get ipset "$1" ipset
	config_get proto "$1" proto all
	config_get src_ip "$1" src_ip
	config_get src_iface "$1" src_iface
	config_get src_port "$1" src_port
	config_get dest_ip "$1" dest_ip
	config_get dest_port "$1" dest_port
	config_get use_policy "$1" use_policy
	config_get family "$1" family any
	config_get rule_logging "$1" logging 0
	config_get global_logging globals logging 0
	config_get loglevel globals loglevel notice

	if [ -n "$src_iface" ]; then
		network_get_device src_dev "$src_iface"
		if [ -z "$src_dev" ]; then
			LOG notice "could not find device corresponding to src_iface $src_iface for rule $1"
			return
		fi
	fi

	[ -z "$dest_ip" ] && unset dest_ip
	[ -z "$src_ip" ] && unset src_ip
	[ -z "$ipset" ] && unset ipset
	[ -z "$src_port" ] && unset src_port
	[ -z "$dest_port" ] && unset dest_port
	if [ "$proto" != 'tcp' ] && [ "$proto" != 'udp' ]; then
		[ -n "$src_port" ] && {
			LOG warn "src_port set to '$src_port' but proto set to '$proto' not tcp or udp. src_port will be ignored"
		}

		[ -n "$dest_port" ] && {
			LOG warn "dest_port set to '$dest_port' but proto set to '$proto' not tcp or udp. dest_port will be ignored"
		}
		unset src_port
		unset dest_port
	fi

	if [ "$1" != "$(echo "$1" | cut -c1-15)" ]; then
		LOG warn "Rule $1 exceeds max of 15 chars. Not setting rule" && return 0
	fi

	if [ -n "$ipset" ]; then
		ipset="-m set --match-set $ipset dst"
	fi

	if [ -z "$use_policy" ]; then
		return
	fi

	if [ "$use_policy" = "default" ]; then
		policy="MARK --set-xmark $MMX_DEFAULT/$MMX_MASK"
	elif [ "$use_policy" = "unreachable" ]; then
		policy="MARK --set-xmark $MMX_UNREACHABLE/$MMX_MASK"
	elif [ "$use_policy" = "blackhole" ]; then
		policy="MARK --set-xmark $MMX_BLACKHOLE/$MMX_MASK"
	else
		rule_policy=1
		policy="mwan3_policy_$use_policy"
		if [ "$sticky" -eq 1 ]; then
			$IPS -! create "mwan3_sticky_v4_$rule" \
			     hash:ip,mark markmask "$MMX_MASK" \
			     timeout "$timeout"
			[ $NO_IPV6 -eq 0 ] &&
				$IPS -! create "mwan3_sticky_v6_$rule" \
				     hash:ip,mark markmask "$MMX_MASK" \
				     timeout "$timeout" family inet6
			$IPS -! create "mwan3_sticky_$rule" list:set
			$IPS -! add "mwan3_sticky_$rule" "mwan3_sticky_v4_$rule"
			[ $NO_IPV6 -eq 0 ] &&
				$IPS -! add "mwan3_sticky_$rule" "mwan3_sticky_v6_$rule"
		fi
	fi

	[ "$ipv" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && return
	[ "$family" = "ipv4" ] && [ "$ipv" = "ipv6" ] && return
	[ "$family" = "ipv6" ] && [ "$ipv" = "ipv4" ] && return

	if [ $rule_policy -eq 1 ] && [ -n "${current##*-N $policy*}" ]; then
		mwan3_push_update -N "$policy"
	fi

	if [ $rule_policy -eq 1 ] && [ "$sticky" -eq 1 ]; then
		if [ -n "${current##*-N mwan3_rule_$1*}" ]; then
			mwan3_push_update -N "mwan3_rule_$1"
		fi

		mwan3_push_update -F "mwan3_rule_$1"
		config_foreach mwan3_set_sticky_iptables interface $ipv


		mwan3_push_update -A "mwan3_rule_$1" \
				  -m mark --mark 0/$MMX_MASK \
				  -j "$policy"
		mwan3_push_update -A "mwan3_rule_$1" \
				  -m mark ! --mark 0xfc00/0xfc00 \
				  -j SET --del-set "mwan3_sticky_$rule" src,src
		mwan3_push_update -A "mwan3_rule_$1" \
				  -m mark ! --mark 0xfc00/0xfc00 \
				  -j SET --add-set "mwan3_sticky_$rule" src,src
		policy="mwan3_rule_$1"
	fi
	if [ "$global_logging" = "1" ] && [ "$rule_logging" = "1" ]; then
		mwan3_push_update -A mwan3_rules \
				  -p "$proto" \
				  ${src_ip:+-s} $src_ip \
				  ${src_dev:+-i} $src_dev \
				  ${dest_ip:+-d} $dest_ip \
				  $ipset \
				  ${src_port:+-m} ${src_port:+multiport} ${src_port:+--sports} $src_port \
				  ${dest_port:+-m} ${dest_port:+multiport} ${dest_port:+--dports} $dest_port \
				  -m mark --mark 0/$MMX_MASK \
				  -m comment --comment "$1" \
				  -j LOG --log-level "$loglevel" --log-prefix "MWAN3($1)"
	fi

	mwan3_push_update -A mwan3_rules \
			  -p "$proto" \
			  ${src_ip:+-s} $src_ip \
			  ${src_dev:+-i} $src_dev \
			  ${dest_ip:+-d} $dest_ip \
			  $ipset \
			  ${src_port:+-m} ${src_port:+multiport} ${src_port:+--sports} $src_port \
			  ${dest_port:+-m} ${dest_port:+multiport} ${dest_port:+--dports} $dest_port \
			  -m mark --mark 0/$MMX_MASK \
			  -j $policy

}

mwan3_set_user_iface_rules()
{
	local current iface update family error device is_src_iface
	iface=$1
	device=$2

	if [ -z "$device" ]; then
		LOG notice "set_user_iface_rules: could not find device corresponding to iface $iface"
		return
	fi

	config_get family "$iface" family ipv4

	if [ "$family" = "ipv4" ]; then
		IPT="$IPT4"
		IPTR="$IPT4R"
	elif [ "$family" = "ipv6" ]; then
		IPT="$IPT6"
		IPTR="$IPT6R"
	fi
	$IPT -S | grep -q "^-A mwan3_rules.*-i $device" && return

	is_src_iface=0

	iface_rule()
	{
		local src_iface
		config_get src_iface "$1" src_iface
		[ "$src_iface" = "$iface" ] && is_src_iface=1
	}
	config_foreach iface_rule rule
	[ $is_src_iface -eq 1 ] && mwan3_set_user_rules
}

mwan3_set_user_rules()
{
	local IPT IPTR ipv
	local current update error

	for ipv in ipv4 ipv6; do
		if [ "$ipv" = "ipv4" ]; then
			IPT="$IPT4"
			IPTR="$IPT4R"
		elif [ "$ipv" = "ipv6" ]; then
			IPT="$IPT6"
			IPTR="$IPT6R"
		fi
		[ "$ipv" = "ipv6" ] && [ $NO_IPV6 -ne 0 ] && continue
		update="*mangle"
		current="$($IPT -S)"


		if [ -n "${current##*-N mwan3_rules*}" ]; then
			mwan3_push_update -N "mwan3_rules"
		fi

		mwan3_push_update -F mwan3_rules

		config_foreach mwan3_set_user_iptables_rule rule "$ipv"

		mwan3_push_update COMMIT
		mwan3_push_update ""
		error=$(echo "$update" | $IPTR 2>&1) || LOG error "set_user_rules: $error"
	done


}

mwan3_set_iface_hotplug_state() {
	local iface=$1
	local state=$2

	echo "$state" > "$MWAN3_STATUS_DIR/iface_state/$iface"
}

mwan3_get_iface_hotplug_state() {
	local iface=$1

	cat "$MWAN3_STATUS_DIR/iface_state/$iface" 2>/dev/null || echo "offline"
}

mwan3_report_iface_status()
{
	local device result track_ips tracking IP IPT

	mwan3_get_iface_id id "$1"
	network_get_device device "$1"
	config_get enabled "$1" enabled 0
	config_get family "$1" family ipv4

	if [ "$family" = "ipv4" ]; then
		IP="$IP4"
		IPT="$IPT4"
	fi

	if [ "$family" = "ipv6" ]; then
		IP="$IP6"
		IPT="$IPT6"
	fi

	if [ -z "$id" ] || [ -z "$device" ]; then
		result="offline"
	elif [ -n "$($IP rule | awk '$1 == "'$((id+1000)):'"')" ] && \
		     [ -n "$($IP rule | awk '$1 == "'$((id+2000)):'"')" ] && \
		     [ -n "$($IPT -S mwan3_iface_in_$1 2> /dev/null)" ] && \
		     [ -n "$($IP route list table $id default dev $device 2> /dev/null)" ]; then
		json_init
		json_add_string section interfaces
		json_add_string interface "$1"
		json_load "$(ubus call mwan3 status "$(json_dump)")"
		json_select "interfaces"
		json_select "$1"
		json_get_vars online uptime
		json_select ..
		json_select ..
		online="$(printf '%02dh:%02dm:%02ds\n' $((online/3600)) $((online%3600/60)) $((online%60)))"
		uptime="$(printf '%02dh:%02dm:%02ds\n' $((uptime/3600)) $((uptime%3600/60)) $((uptime%60)))"
		result="$(mwan3_get_iface_hotplug_state $1) $online, uptime $uptime"
	elif [ -n "$($IP rule | awk '$1 == "'$((id+1000)):'"')" ] || \
		     [ -n "$($IP rule | awk '$1 == "'$((id+2000)):'"')" ] || \
		     [ -n "$($IP rule | awk '$1 == "'$((id+3000)):'"')" ] || \
		     [ -n "$($IPT -S mwan3_iface_in_$1 2> /dev/null)" ] || \
		     [ -n "$($IP route list table $id default dev $device 2> /dev/null)" ]; then
		result="error"
	elif [ "$enabled" = "1" ]; then
		result="offline"
	else
		result="disabled"
	fi

	mwan3_list_track_ips()
	{
		track_ips="$1 $track_ips"
	}
	config_list_foreach "$1" track_ip mwan3_list_track_ips

	if [ -n "$track_ips" ]; then
		if [ -n "$(pgrep -f "mwan3track $1 $device")" ]; then
			tracking="active"
		else
			tracking="down"
		fi
	else
		tracking="not enabled"
	fi

	echo " interface $1 is $result and tracking is $tracking"
}

mwan3_report_policies()
{
	local ipt="$1"
	local policy="$2"

	local percent total_weight weight iface

	total_weight=$($ipt -S "$policy" | grep -v '.*--comment "out .*" .*$' | cut -s -d'"' -f2 | head -1 | awk '{print $3}')

	if [ -n "${total_weight##*[!0-9]*}" ]; then
		for iface in $($ipt -S "$policy" | grep -v '.*--comment "out .*" .*$' | cut -s -d'"' -f2 | awk '{print $1}'); do
			weight=$($ipt -S "$policy" | grep -v '.*--comment "out .*" .*$' | cut -s -d'"' -f2 | awk '$1 == "'$iface'"' | awk '{print $2}')
			percent=$((weight*100/total_weight))
			echo " $iface ($percent%)"
		done
	else
		echo " $($ipt -S "$policy" | grep -v '.*--comment "out .*" .*$' | sed '/.*--comment \([^ ]*\) .*$/!d;s//\1/;q')"
	fi
}

mwan3_report_policies_v4()
{
	local policy

	for policy in $($IPT4 -S | awk '{print $2}' | grep mwan3_policy_ | sort -u); do
		echo "$policy:" | sed 's/mwan3_policy_//'
		mwan3_report_policies "$IPT4" "$policy"
	done
}

mwan3_report_policies_v6()
{
	local policy

	for policy in $($IPT6 -S | awk '{print $2}' | grep mwan3_policy_ | sort -u); do
		echo "$policy:" | sed 's/mwan3_policy_//'
		mwan3_report_policies "$IPT6" "$policy"
	done
}

mwan3_report_connected_v4()
{
	if [ -n "$($IPT4 -S mwan3_connected 2> /dev/null)" ]; then
		$IPS -o save list mwan3_connected_v4 | grep add | cut -d " " -f 3
	fi
}

mwan3_report_connected_v6()
{
	if [ -n "$($IPT6 -S mwan3_connected 2> /dev/null)" ]; then
		$IPS -o save list mwan3_connected_v6 | grep add | cut -d " " -f 3
	fi
}

mwan3_report_rules_v4()
{
	if [ -n "$($IPT4 -S mwan3_rules 2> /dev/null)" ]; then
		$IPT4 -L mwan3_rules -n -v 2> /dev/null | tail -n+3 | sed 's/mark.*//' | sed 's/mwan3_policy_/- /' | sed 's/mwan3_rule_/S /'
	fi
}

mwan3_report_rules_v6()
{
	if [ -n "$($IPT6 -S mwan3_rules 2> /dev/null)" ]; then
		$IPT6 -L mwan3_rules -n -v 2> /dev/null | tail -n+3 | sed 's/mark.*//' | sed 's/mwan3_policy_/- /' | sed 's/mwan3_rule_/S /'
	fi
}

mwan3_flush_conntrack()
{
	local interface="$1"
	local action="$2"

	handle_flush() {
		local flush_conntrack="$1"
		local action="$2"

		if [ "$action" = "$flush_conntrack" ]; then
			echo f > ${CONNTRACK_FILE}
			LOG info "Connection tracking flushed for interface '$interface' on action '$action'"
		fi
	}

	if [ -e "$CONNTRACK_FILE" ]; then
		config_list_foreach "$interface" flush_conntrack handle_flush "$action"
	fi
}

mwan3_track_clean()
{
	rm -rf "${MWAN3_STATUS_DIR:?}/${1}" &> /dev/null
	rmdir --ignore-fail-on-non-empty "$MWAN3_STATUS_DIR"
}
