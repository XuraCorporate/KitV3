#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#####
# Function to exit in case of error
#####
function exit_for_error {
        #####
        # The message to print
        #####
        _MESSAGE=$1

        #####
        # If perform a change directory in case something has failed in order to not be in deploy dir
        #####
        _CHANGEDIR=$2

        #####
        # If hard "exit 1"
        # If break "break"
        # If soft no exit
        #####
        _EXIT=${3-hard}
	_EXEC=${4-true}
	${_EXEC} >/dev/null 2>&1
        if ${_CHANGEDIR} && [[ "${_EXIT}" == "hard" ]]
        then
                cd ${_CURRENTDIR}
        fi
        if [[ "${_EXIT}" == "hard" ]]
        then
                echo -e "${RED}${_MESSAGE}${NC}"
                exit 1
        elif [[ "${_EXIT}" == "break" ]]
        then
                echo -e "${RED}${_MESSAGE}${NC}"
                break
        elif [[ "${_EXIT}" == "soft" ]]
        then
                echo -e "${YELLOW}${_MESSAGE}${NC}"
        fi
}

function csv_validation {
        #echo -e -n "   - Verifying unit $(echo ${_UNITTOBEVALIDATED}|awk '{ print toupper($0) }') CSV file ${_CSV} ...\t\t"
        if [ ! -f ${_CSV} ] || [ ! -r ${_CSV} ] || [ ! -s ${_CSV} ]
        then
                exit_for_error "CSV File ${_CSV} Network with mapping PortID,MacAddress,FixedIP does not exist." false soft
        fi
        #echo -e "${GREEN} [OK]${NC}"
}

function net_validation {
        _NET=$1
        _NAME=$2
        _NETWORK=$(cat ${_ENV}|awk '/'${_NET}'_network_name/ {print $2}'|sed "s/\"//g")
        _VLAN=$(cat ${_ENV}|awk '/'${_NET}'_network_vlan/ {print $2}'|sed "s/\"//g")

        #####
        # Check the Network exist
        #####
        #echo -e -n " - Validating chosen ${_NAME} Network: ${_NETWORK} ...\t\t"
        neutron net-show "${_NETWORK}" >/dev/null 2>&1 || exit_for_error "Error, ${_NET} Network is not present." true hard
        #echo -e "${GREEN} [OK]${NC}"

        #####
        # Check the VLAN ID is corret
        # - none
        # - between 1 to 4096
        #####
        #echo -e -n "   - Validating VLAN ${_VLAN} for chosen ${_NAME} Network ${_NETWORK} ...\t\t"
        if [[ "${_VLAN}" != "none" ]]
        then
                if (( ${_VLAN} < 1 || ${_VLAN} > 4096 ))
                then
                        exit_for_error "Error, The VLAN ID ${_VLAN} for the ${_NET} Network is not valid. Acceptable values: \"none\" or a number between 1 to 4096." true hard
                fi
        fi
        #echo -e "${GREEN} [OK]${NC}"
}

function port_validation {
        _PORT=$1
        _MAC=$2

        #####
        # Check of the port exist
        #####
        #echo -e -n "     - Validating Port ${_PORT} exist ...\t\t\t"
        neutron port-show ${_PORT} >/dev/null 2>&1 || exit_for_error "Error, Port with ID ${_PORT} does not exist." false break
        #echo -e "${GREEN} [OK]${NC}"

        #####
        # Check if the Mac address is the same from the given one
        #####
        #echo -e -n "     - Validating Port ${_PORT} MAC Address ...\t\t"
        if [[ "$(neutron port-show --field mac_address --format value ${_PORT})" != "${_MAC}" ]]
        then
                exit_for_error "Error, Port with ID ${_PORT} has a different MAC Address than the one provided into the CSV file." false break
        fi
        #echo -e "${GREEN} [OK]${NC}"
}

function ip_validation {
        _IP=$1

        #####
        # Check if the given IP or NetMask is valid
        #####
        #echo -e -n "     - Validating IP Address ${_IP} ...\t\t\t\t\t\t"
        echo ${_IP}|grep -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" >/dev/null 2>&1
        if [[ "${?}" != "0" ]]
        then
                exit_for_error "Error, The Address ${_IP} is not valid." true hard
        fi
        if (( "$(echo ${_IP}|awk -F "." '{print $1}')" < "1" || "$(echo ${_IP}|awk -F "." '{print $1}')" > "255" ))
        then
                exit_for_error "Error, The Address ${_IP} is not valid." true hard
        fi
        if (( "$(echo ${_IP}|awk -F "." '{print $2}')" < "0" || "$(echo ${_IP}|awk -F "." '{print $2}')" > "255" ))
        then
                exit_for_error "Error, The Address ${_IP} is not valid." true hard
        fi
        if (( "$(echo ${_IP}|awk -F "." '{print $3}')" < "0" || "$(echo ${_IP}|awk -F "." '{print $3}')" > "255" ))
        then
                exit_for_error "Error, The Address ${_IP} is not valid." true hard
        fi
        if (( "$(echo ${_IP}|awk -F "." '{print $4}')" < "0" || "$(echo ${_IP}|awk -F "." '{print $4}')" > "255" ))
        then
                exit_for_error "Error, The Address ${_IP} is not valid." true hard
        fi
        #echo -e "${GREEN} [OK]${NC}"
}

function mac_validation {
        _MAC=$1

        #####
        # Check if the given IP or NetMask is valid
        #####
        #echo -e -n "     - Validating MAC Address ${_MAC} ...\t\t\t\t\t"
        echo ${_MAC}|grep -E "([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})" >/dev/null 2>&1
        if [[ "${?}" != "0" ]]
        then
                exit_for_error "Error, The Port Mac Address ${_MAC} is not valid." true hard
        fi
        #echo -e "${GREEN} [OK]${NC}"
}

if [[ "${1}" == "" ]]
then
	set -- "${@:1}" "--help"
fi
while [[ $# -gt 0 ]]
do
	key="$1"
	case $key in
		-e|--env)
	    		_ENVFOLDER="$2"
	    		shift
	    		;;
		-h|--help)
			echo "Help for System Resource Validation phase"
			echo "-e|--env <envirnment folder - e.g Environments/Dev_environment>"
			echo "-h|--help"
			exit 0
			shift
			;;
		*)
			echo "Unknown option $1 $2"
			shift
			;;
	esac
	shift
done

_OPENSTACKRC="${_ENVFOLDER}/OpenStackRC/openstackrc"
ls "${_OPENSTACKRC}" >/dev/null 2>&1 || exit_for_error "Environment path is not valid ${_ENVFOLDER}" false hard

_ENV="${_ENVFOLDER}/common.yaml"
if [ ! -f ${_ENV} ] || [ ! -r ${_ENV} ] || [ ! -s ${_ENV} ]
then
        exit_for_error "Error, Environment file is missing." false hard
fi

#####
# Unload any previous loaded environment file
#####
for _BASHENV in $(env|grep ^OS|awk -F "=" '{print $1}')
do
        unset ${_BASHENV}
done

#####
# Load environment file
#####
source ${_OPENSTACKRC}

for _UNITTOBEVALIDATED in "cms" "dsu" "lvu" "mau" "omu" "smu" "vm-asu"
do
        _IMAGE=$(cat ${_ENV}|grep "$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_image"|grep -v -E "image_id|image_source|image_volume_size"|awk '{print $2}'|sed "s/\"//g")
        _VOLUMEID=$(cat ${_ENV}|awk '/'$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_volume_id'/ {print $2}'|sed "s/\"//g")
        _FLAVOR=$(cat ${_ENV}|awk '/'$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_flavor_name'/ {print $2}'|sed "s/\"//g")
        _SOURCE=$(cat ${_ENV}|grep "$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_image_source"|awk '{print $2}'|sed "s/\"//g")

        #####
        # _SOURCE=glance -> Check the Image Id and the Image Name is the same 
        # _SOURCE=cinder -> Check the Volume Id, the Given size and if the Volume snapshot/clone feature is present 
        #####
        if [[ "${_SOURCE}" == "glance" ]]
        then
		_IMAGEID=$(glance image-list|awk '/ '${_IMAGE}' / {print $2}')
		if (( "$( echo "${_IMAGEID}"|wc -l)" > "1" ))
		then
			echo -e "${RED}" "Image for Unit ${_UNITTOBEVALIDATED} has multiple source" "${NC}"
			echo -e "${RED}" "${_IMAGEID}" "${NC}"
			exit_for_error "Error" true hard
		elif [[ "${_IMAGEID}" == "" ]]
		then
                	exit_for_error "Error, Image for Unit ${_UNITTOBEVALIDATED} is not present or mismatch between ID and Name." true hard
		fi
        elif [[ "${_SOURCE}" == "cinder" ]]
        then
		_VOLUME_DETAILS=$(cinder show ${_VOLUMEID} 2>/dev/null)
		if [[ "$?" != "0" ]]
		then
			exit_for_error "Error, Volume for Unit ${_UNITTOBEVALIDATED} not present." true hard
		fi
                _VOLUME_SIZE=$(echo "${_VOLUME_DETAILS}"|awk '/ size / {print $4}'|sed "s/ //g")
                _VOLUME_GIVEN_SIZE=$(cat ${_ENV}|awk '/'$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_volume_size'/ {print $2}'|sed "s/\"//g")
                if (( "${_VOLUME_GIVEN_SIZE}" < "${_VOLUME_SIZE}" ))
                then
                        exit_for_error "Error, Volume for Unit ${_UNITTOBEVALIDATED} with UUID ${_VOLUMEID} has a size of ${_VOLUME_SIZE} which cannot fit into the given input size of ${_VOLUME_GIVEN_SIZE}." true hard
                fi

                #####
                # Creating a test volume to verify that the snapshotting works
                # https://wiki.openstack.org/wiki/CinderSupportMatrix
                # e.g. Feature not available with standard NFS driver
                #####
                #####
                # Creating a new volume from the given one
                #####
                cinder create --source-volid ${_VOLUMEID} --display-name "temp-${_VOLUMEID}" ${_VOLUME_SIZE} >/dev/null 2>&1 || exit_for_error "Error, During volume cloning/snapshotting. With the current Cinder's backend Glance has to be used." true hard "cinder delete temp-${_VOLUMEID}"

                #####
                # Wait until the volume created is in error or available states
                #####
                while :
                do
                        _VOLUME_SOURCE_STATUS=$(cinder show temp-${_VOLUMEID}|grep " status "|awk '{print $4}')
                        if [[ "${_VOLUME_SOURCE_STATUS}" == "available" ]]
                        then
                                cinder delete temp-${_VOLUMEID} >/dev/null 2>&1
                                break
                        elif [[ "${_VOLUME_SOURCE_STATUS}" == "error" ]]
                        then
                                cinder delete temp-${_VOLUMEID} >/dev/null 2>&1
                                exit_for_error "Error, the system does not support volume cloning/snapshotting. With the current Cinder's backend Glance has to be used." true hard
                        fi
                done
        else
                exit_for_error "Error, Invalid Image Source option, can be \"glance\" or \"cinder\"." true hard
        fi

        #####
        # Check the given flavor is available
        #####
        nova flavor-show "${_FLAVOR}" >/dev/null 2>&1 || exit_for_error "Error, Flavor for Unit ${_UNITTOBEVALIDATED} not present." true hard
done

#echo -e "\n${GREEN}${BOLD}Verifying Units CVS Files${NC}${NORMAL}"
for _UNITTOBEVALIDATED in "cms" "dsu" "lvu" "mau" "omu" "smu" "vm-asu"
do
        _CSVFILEPATH=${_ENVFOLDER}/${_UNITTOBEVALIDATED}
        _ADMINCSVFILE=$(echo ${_CSVFILEPATH}/admin.csv)
        _SZCSVFILE=$(echo ${_CSVFILEPATH}/sz.csv)
        _SIPCSVFILE=$(echo ${_CSVFILEPATH}/sip.csv)
        _MEDIACSVFILE=$(echo ${_CSVFILEPATH}/media.csv)

        #echo -e " - $(echo ${_UNITTOBEVALIDATED}|awk '{ print toupper($0) }')"
        for _CSV in "${_ADMINCSVFILE}" "${_SZCSVFILE}" "${_SIPCSVFILE}" "${_MEDIACSVFILE}"
        do
                #####
                # Check if the CSV File
                # - Does it exist?
                # - Is it readable?
                # - Does it have a size higher than 0Byte?
                # - Does it have the given starting line?
                # - Does it have the given ending line?
                #####
                if [[ "${_UNITTOBEVALIDATED}" == "cms" ]] && [[ "${_CSV}" =~ "sip.csv" || "${_CSV}" =~ "media.csv" ]]
                then
                        csv_validation
                fi

                if [[ "${_UNITTOBEVALIDATED}" != "mau" ]] && [[ "${_CSV}" =~ "sz.csv" ]]
                then
                        csv_validation
                fi

                if [[ "${_CSV}" =~ "admin.csv" ]]
                then
                        csv_validation
                fi
        done
done

#echo -e "\n${GREEN}${BOLD}Verifying OpenStack Neutron Network${NC}${NORMAL}"
for _NETWORK in "admin" "sz" "sip" "media"
do
        net_validation ${_NETWORK} $(echo ${_NETWORK}|awk '{ print toupper($0) }')
done

#echo -e "\n${GREEN}${BOLD}Verifying OpenStack Neutron Ports${NC}${NORMAL}"
_OLDIFS=$IFS
IFS=","
for _UNITTOBEVALIDATED in "cms" "dsu" "lvu" "mau" "omu" "smu" "vm-asu"
do
        _CSVFILEPATH=${_ENVFOLDER}/${_UNITTOBEVALIDATED}
        _ADMINCSVFILE=$(echo ${_CSVFILEPATH}/admin.csv)
        _SZCSVFILE=$(echo ${_CSVFILEPATH}/sz.csv)
        _SIPCSVFILE=$(echo ${_CSVFILEPATH}/sip.csv)
        _MEDIACSVFILE=$(echo ${_CSVFILEPATH}/media.csv)

        #echo -e " - $(echo ${_UNITTOBEVALIDATED}|awk '{ print toupper($0) }')"
        for _CSV in "${_ADMINCSVFILE}" "${_SZCSVFILE}" "${_SIPCSVFILE}" "${_MEDIACSVFILE}"
        do
                if [[ "${_CSV}" =~ "admin.csv" ]]
                then
                        #echo -e "   - OpenStack Admin Neutron Ports"
                        while read _PORTID _MAC _IP
                        do
                                mac_validation ${_MAC}
                                port_validation ${_PORTID} ${_MAC}
                                ip_validation ${_IP}
                        done <<< "$(cat ${_ADMINCSVFILE})"
                fi

                if [[ "${_UNITTOBEVALIDATED}" != "mau" ]] && [[ "${_CSV}" =~ "sz.csv" ]]
                then
                        #echo -e "   - OpenStack Secure Zone Neutron Ports"
                        while read _PORTID _MAC _IP
                        do
                                mac_validation ${_MAC}
                                port_validation ${_PORTID} ${_MAC}
                                ip_validation ${_IP}
                        done <<< "$(cat ${_SZCSVFILE})"
                fi

                if [[ "${_UNITTOBEVALIDATED}" == "cms" ]] && [[ "${_CSV}" =~ "sip.csv" ]]
                then
                        #echo -e "   - OpenStack SIP Neutron Ports"
                        while read _PORTID _MAC _IP
                        do
                                mac_validation ${_MAC}
                                port_validation ${_PORTID} ${_MAC}
                                ip_validation ${_IP}
                        done <<< "$(cat ${_SIPCSVFILE})"
                fi

                if [[ "${_UNITTOBEVALIDATED}" == "cms" ]] && [[ "${_CSV}" =~ "media.csv" ]]
                then
                        #echo -e "   - OpenStack Media Neutron Ports"
                        while read _PORTID _MAC _IP
                        do
                                mac_validation ${_MAC}
                                port_validation ${_PORTID} ${_MAC}
                                ip_validation ${_IP}
                        done <<< "$(cat ${_MEDIACSVFILE})"
                fi
        done
done
IFS=${_OLDIFS}

for _NETWORK in "admin" "sz" "sip" "media"
do
	if $(cat ${_ENV}|awk '/'${_NETWORK}'_security_group_enabled/ {print tolower($2)}')
	then
		_SECGROUP=$(cat ${_ENV}|awk '/'${_NETWORK}'_security_group_name/ {print $2}')
		neutron security-group-show ${_SECGROUP} >/dev/null 2>&1 || exit_for_error "Error, missing security group ${_SECGROUP} for network ${_NETWORK}" false hard
	fi
done

# Add server group validation

exit 0
