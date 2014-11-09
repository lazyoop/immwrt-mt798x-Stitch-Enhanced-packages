# sample script for sending user defined updates 
# 2014 Christian Schoenebeck <christian dot schoenebeck at gmail dot com>
#
# activated inside /etc/config/ddns by setting
#
# option update_script '/usr/lib/ddns/update_sample.sh' 
#
# the script is parsed (not executed) inside send_update() function
# of /usr/lib/ddns/dynamic_dns_functions.sh
# so you can use all available functions and global variables inside this script
# already defined in dynamic_dns_updater.sh and dynamic_dns_functions.sh
#
# It make sence to define the update url ONLY inside this script 
# because it's anyway unique to the update script
# otherwise it should work with the default scripts
#
# the code here is the copy of the default used inside send_update()
#
local __ANSWER
# tested with spdns.de
local __URL="http://[USERNAME]:[PASSWORD]@update.spdns.de/nic/update?hostname=[DOMAIN]&myip=[IP]"

# do replaces in URL
__URL=$(echo $__URL | sed -e "s#\[USERNAME\]#$URL_USER#g" -e "s#\[PASSWORD\]#$URL_PASS#g" \
			       -e "s#\[DOMAIN\]#$domain#g" -e "s#\[IP\]#$__IP#g")
[ $use_https -ne 0 ] && __URL=$(echo $__URL | sed -e 's#^http:#https:#')

do_transfer __ANSWER "$__URL" || return 1

write_log 7 "DDNS Provider answered:\n$__ANSWER"

# analyse provider answers
# "good [IP_ADR]"	= successful
# "nochg [IP_ADR]"	= no change but OK
echo "$__ANSWER" | grep -E "good|nochg" >/dev/null 2>&1
return $?	# "0" if "good" or "nochg" found

