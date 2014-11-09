#
# script for sending updates to no-ip.com / noip.com
# 2014 Christian Schoenebeck <christian dot schoenebeck at gmail dot com>
#
# This script is parsed by dynamic_dns_functions.sh inside send_update() function
#
# provider did not reactivate records, if no IP change was recognized
# so we send a dummy (localhost) and a seconds later we send the correct IP addr
#
local __ANSWER __LH
local __UPDURL="http://[USERNAME]:[PASSWORD]@dynupdate.no-ip.com/nic/update?hostname=[DOMAIN]&myip=[IP]"

# set IP version dependend dummy (localhost)
[ $use_ipv6 -eq 0 ] && __LH="127.0.0.1" || __LH="::1"

# lets do DUMMY transfer
write_log 7 "sending dummy IP to 'no-ip.com'"
__URL=$(echo $__UPDURL | sed -e "s#\[USERNAME\]#$URL_USER#g" -e "s#\[PASSWORD\]#$URL_PASS#g" \
			       -e "s#\[DOMAIN\]#$domain#g" -e "s#\[IP\]#$__LH#g")
[ $use_https -ne 0 ] && __URL=$(echo $__URL | sed -e 's#^http:#https:#')

do_transfer __ANSWER "$__URL" || return 1

write_log 7 "'no-ip.com' answered:\n$__ANSWER"
# analyse provider answers
# "good [IP_ADR]"	= successful
# "nochg [IP_ADR]"	= no change but OK
echo "$__ANSWER" | grep -E "good|nochg" >/dev/null 2>&1 || return 1

# lets wait a seconds
sleep 1

# now send the correct data
write_log 7 "sending real IP to 'no-ip.com'"
__URL=$(echo $__UPDURL | sed -e "s#\[USERNAME\]#$URL_USER#g" -e "s#\[PASSWORD\]#$URL_PASS#g" \
			       -e "s#\[DOMAIN\]#$domain#g" -e "s#\[IP\]#$__IP#g")
[ $use_https -ne 0 ] && __URL=$(echo $__URL | sed -e 's#^http:#https:#')

do_transfer __ANSWER "$__URL" || return 1

write_log 7 "'no-ip.com' answered:\n$__ANSWER"
# analyse provider answers
# "good [IP_ADR]"	= successful
# "nochg [IP_ADR]"	= no change but OK
echo "$__ANSWER" | grep -E "good|nochg" >/dev/null 2>&1
return $?	# "0" if "good" or "nochg" found

