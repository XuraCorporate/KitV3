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
                        echo -e "${RED}Unknown option $1 $2${NC}"
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

echo -e "\n${GREEN}${BOLD}Verifying Units Images${NC}${NORMAL}"
for _UNITTOBEVALIDATED in "cms" "dsu" "lvu" "mau" "omu" "smu" "vm-asu"
do
        _IMAGE=$(cat ${_ENV}|grep "$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_image"|grep -v -E "image_id|image_source|image_volume_size"|awk '{print $2}'|sed "s/\"//g")
        _VOLUMEID=$(cat ${_ENV}|awk '/'$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_volume_id'/ {print $2}'|sed "s/\"//g")
        _SOURCE=$(cat ${_ENV}|grep "$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_image_source"|awk '{print $2}'|sed "s/\"//g")

        #####
        # _SOURCE=glance -> Check the Image Id and the Image Name is the same 
        # _SOURCE=cinder -> Check the Volume Id, the Given size and if the Volume snapshot/clone feature is present 
        #####
        if [[ "${_SOURCE}" == "glance" ]]
        then
                if $(cat ${_ENV}|awk '/'${_UNITTOBEVALIDATED}'_local_boot/ {print $2}'|awk '{print tolower($0)}')
                then
                        echo -e " - ${GREEN}The Unit ${_UNITTOBEVALIDATED} will boot from the local hypervisor disk (aka Ephemeral Disk)${NC}"
                else
                        echo -e " - ${GREEN}The Unit ${_UNITTOBEVALIDATED} will boot from Volume (aka from the SAN)${NC}"
                fi

                echo -e -n "   - Validating chosen Glance Image ${_IMAGE} ...\t"
		_IMAGEID=$(glance image-list|awk '/ '${_IMAGE}' / {print $2}')
		if (( "$( echo "${_IMAGEID}"|wc -l)" > "1" ))
		then
			echo -e "${RED}" "Image for Unit ${_UNITTOBEVALIDATED} has multiple source" "${NC}"
			echo -e "${RED}" "${_IMAGEID}" "${NC}"
			exit_for_error "Error" true hard
		elif [[ "${_IMAGEID}" == "" ]]
		then
                	exit_for_error "Error, Image for Unit ${_UNITTOBEVALIDATED} is not present or it mismatches between ID and Name." true hard
		fi
		echo -e "${GREEN} [OK]${NC}"

        elif [[ "${_SOURCE}" == "cinder" ]]
        then
                echo -e " - ${GREEN}The Unit ${_UNITTOBEVALIDATED} will boot from Volume (aka from the SAN)${NC}"

                echo -e -n "   - Validating chosen Cinder Volume ${_VOLUMEID} ...\t\t\t\t"
		_VOLUME_DETAILS=$(cinder show ${_VOLUMEID} 2>/dev/null)
		if [[ "$?" != "0" ]]
		then
			exit_for_error "Error, Volume for Unit ${_UNITTOBEVALIDATED} not present." true hard
		fi
                echo -e "${GREEN} [OK]${NC}"

		echo -e -n "   - Validating given volume size ...\t\t\t\t\t\t\t\t"
                _VOLUME_SIZE=$(echo "${_VOLUME_DETAILS}"|awk '/ size / {print $4}'|sed "s/ //g")
                _VOLUME_GIVEN_SIZE=$(cat ${_ENV}|awk '/'$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_volume_size'/ {print $2}'|sed "s/\"//g")
                if (( "${_VOLUME_GIVEN_SIZE}" < "${_VOLUME_SIZE}" ))
                then
                        exit_for_error "Error, Volume for Unit ${_UNITTOBEVALIDATED} with UUID ${_VOLUMEID} has a size of ${_VOLUME_SIZE} which cannot fit into the given input size of ${_VOLUME_GIVEN_SIZE}." true hard
                fi
		echo -e "${GREEN} [OK]${NC}"

                #####
                # Creating a test volume to verify that the snapshotting works
                # https://wiki.openstack.org/wiki/CinderSupportMatrix
                # e.g. Feature not available with standard NFS driver
                #####
		echo -e -n "   - Validating if volume cloning/snapshotting feature is available ...\t\t\t"
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
				echo -e "${GREEN} [OK]${NC}"
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
done

exit 0
