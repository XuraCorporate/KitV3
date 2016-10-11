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
		-s|--source)
	    		_VMID="$2"
	    		shift
	    		;;
		-h|--help)
			echo "Help for Golden Image Creator"
			echo "-e|--env <envirnment folder - e.g Environments/Dev_environment>"
			echo "-s|--source <nova image uuid or name - e.g. e59bd794-08c8-41ff-8b2a-dede6fbc06a0 or V1VTUS001XUR-SMU1A>"
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

if [[ "${_VMID}" == "" ]]
then
	exit_for_error "Missing VM UUID/Name ${_VMID}" false hard
else
	_VMSTATUS=$(nova show ${_VMID} 2>/dev/null)
	if [[ "${_VMSTATUS}" == "" ]]
	then
		exit_for_error "Invalid VM UUID/Name - ${_VMID}" false hard
	elif [[ "$(echo ${_VMSTATUS}|awk '/ OS-EXT-STS:task_state / {print $4}')" == "-" ]]
	then
		exit_for_error "The given VM ${_VMID} has an invalid task state" false hard
	fi
fi

for _BASHENV in $(env|grep ^OS|awk -F "=" '{print $1}')
do
        unset ${_BASHENV}
done
source ${_OPENSTACKRC}

_TMPSNAPSHOTNAME=$(echo tmp-$(date "+%Y%m%d%H%M%S"))
_VMNAME=$(echo "${_VMSTATUS}"|awk '/ name / {print $4}'|sed "s/ //g")

nova image-create ${_VMID} ${_TMPSNAPSHOTNAME}||exit_for_error "Error Snapshotting the VM ${_VMID}" false hard
_SNAPSHOTID=$(glance image-list|awk '/ '${_TMPSNAPSHOTNAME}' / {print $2}')
while :; do glance image-show ${_SNAPSHOTID}|awk '/ status / {print $4}'|grep "active" && break; done >/dev/null 2>&1 
mkdir tmp
glance image-download ${_SNAPSHOTID} --file ./tmp/tmp >/dev/null 2>&1\
	||exit_for_error "Error downloading the snapshot for ${_VMID}" false hard \
	"rm -fr ./tmp ; glance image-delete ${_SNAPSHOTID}" 
qemu-img convert -c -q -f qcow2 -O qcow2 ./tmp/tmp ./tmp/${_VMNAME}

glance image-delete ${_SNAPSHOTID}
rm -f ./tmp/tmp

bash Tools/ImageLoader.sh --env ${_ENVFOLDER} -i tmp/

rm -rf ./tmp

exit 0
