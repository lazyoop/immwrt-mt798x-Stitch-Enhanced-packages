#!/bin/sh

. /lib/functions.sh

STOP=$1
ACTIVE_STATE_PREFIX="SQM_active_on_"
ACTIVE_STATE_FILE_DIR="/var/run/SQM"
mkdir -p ${ACTIVE_STATE_FILE_DIR}

# the current uci config file does not necessarily contain sections for all interfaces with active
# SQM instances, so use the ACTIVE_STATE_FILES to detect the interfaces on which to stop SQM.
# Currently the .qos scripts start with stopping any existing traffic shaping so this should not
# effectively change anything...
PROTO_STATE_FILE_LIST=$( ls ${ACTIVE_STATE_FILE_DIR}/${ACTIVE_STATE_PREFIX}* 2> /dev/null )
for STATE_FILE in ${PROTO_STATE_FILE_LIST} ; do
    if [ -f ${STATE_FILE} ] ;
    then
	STATE_FILE_BASE_NAME=$( basename ${STATE_FILE} )
	CURRENT_INTERFACE=${STATE_FILE_BASE_NAME:${#ACTIVE_STATE_PREFIX}:$(( ${#STATE_FILE_BASE_NAME} - ${#ACTIVE_STATE_PREFIX} ))}        
	logger -t SQM -s "Stopping SQM on interface: ${CURRENT_INTERFACE}"
	/usr/lib/sqm/stop.sh ${CURRENT_INTERFACE}
	rm ${STATE_FILE}	# well, we stop it so it is not running anymore and hence no active state file needed...
    fi
done

config_load sqm

run_simple_qos() {
	local section="$1"
	export IFACE=$(config_get "$section" interface)
	ACTIVE_STATE_FILE_FQN="${ACTIVE_STATE_FILE_DIR}/${ACTIVE_STATE_PREFIX}${IFACE}"	# this marks interfaces as active with SQM
	[ -f "${ACTIVE_STATE_FILE_FQN}" ] && logger -t SQM -s "Uh, oh, ${ACTIVE_STATE_FILE_FQN} should already be stopped."	# Not supposed to happen

	if [ $(config_get "$section" enabled) -ne 1 ];
	then
	    if [ -f "${ACTIVE_STATE_FILE_FQN}" ];
	    then
		# this should not be possible, delete after testing
		local SECTION_STOP="stop"	# it seems the user just de-selected enable, so stop the active SQM
	    else
		logger -t SQM -s "SQM for interface ${IFACE} is not enabled, skipping over..."
		return 0	# since SQM is not active on the current interface nothing to do here
	    fi
	fi

	export UPLINK=$(config_get "$section" upload)
	export DOWNLINK=$(config_get "$section" download)
	export LLAM=$(config_get "$section" linklayer_adaptation_mechanism)
	export LINKLAYER=$(config_get "$section" linklayer)
	export OVERHEAD=$(config_get "$section" overhead)
	export STAB_MTU=$(config_get "$section" tcMTU)
	export STAB_TSIZE=$(config_get "$section" tcTSIZE)
	export STAB_MPU=$(config_get "$section" tcMPU)
	export ILIMIT=$(config_get "$section" ilimit)
	export ELIMIT=$(config_get "$section" elimit)
	export ITARGET=$(config_get "$section" itarget)
	export ETARGET=$(config_get "$section" etarget)
	export IECN=$(config_get "$section" ingress_ecn)
	export EECN=$(config_get "$section" egress_ecn)
	export IQDISC_OPTS=$(config_get "$section" iqdisc_opts)
	export EQDISC_OPTS=$(config_get "$section" eqdisc_opts)
	export TARGET=$(config_get "$section" target)
	export SQUASH_DSCP=$(config_get "$section" squash_dscp)
	export SQUASH_INGRESS=$(config_get "$section" squash_ingress)

	export QDISC=$(config_get "$section" qdisc)
	export SCRIPT=/usr/lib/sqm/$(config_get "$section" script)

#	# there should be nothing left to stop, so just avoid calling the script
	if [ "$STOP" == "stop" -o "$SECTION_STOP" == "stop" ];
	then 
#	     /usr/lib/sqm/stop.sh
#	     [ -f ${ACTIVE_STATE_FILE_FQN} ] && rm ${ACTIVE_STATE_FILE_FQN}	# conditional to avoid errors ACTIVE_STATE_FILE_FQN does not exist anymore
#	     $(config_set "$section" enabled 0)	# this does not save to the config file only to the loaded memory representation
#	     logger -t SQM -s "SQM qdiscs on ${IFACE} removed"
	     return 0
	fi
	logger -t SQM -s "Queue Setup Script: ${SCRIPT}"
	[ -x "$SCRIPT" ] && { $SCRIPT ; touch ${ACTIVE_STATE_FILE_FQN}; }
}

config_foreach run_simple_qos
