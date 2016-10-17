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
		-n|--name)
	    		_NAME="$2"
	    		shift
	    		;;
		-h|--help)
			echo "Help for Golden Image Creator"
			echo "-e|--env <envirnment folder - e.g Environments/Dev_environment>"
			echo "-s|--source <nova image uuid or name - e.g. e59bd794-08c8-41ff-8b2a-dede6fbc06a0 or V1VTUS001XUR-SMU1A>"
			echo "-n|--name <image name to be used - e.g swp-RedHat-Linux-OS-KVM-1.1.0.0-02_6.6.1.0-01>"
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
if [[ "${_NAME}" == "" ]]
then
	exit_for_error "Missing Image Name to be Used" false hard
fi

echo -e "${GREEN}Golden Image Maker${NC}"

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

_TMPSNAPSHOTNAME=$(echo tmp-$(date "+%Y%m%d%H%M%S"))
_VMNAME=$(echo "${_VMSTATUS}"|awk '/ name / {print $4}'|sed "s/ //g")

echo -e -n " - Creating VM ${_VMNAME} snapshot ...\t\t"
nova image-create ${_VMID} ${_TMPSNAPSHOTNAME}||exit_for_error "Error Snapshotting the VM ${_VMID}" false hard
_SNAPSHOTID=$(glance image-list|awk '/ '${_TMPSNAPSHOTNAME}' / {print $2}')
while :; do glance image-show ${_SNAPSHOTID}|awk '/ status / {print $4}'|grep "active" && break; done >/dev/null 2>&1 
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Downloading VM ${_VMNAME} snapshot ...\t\t"
glance image-download ${_SNAPSHOTID} --file ./tmp >/dev/null 2>&1\
	||exit_for_error "Error downloading the snapshot for ${_VMID}" false hard \
	"rm -fr ./tmp ; glance image-delete ${_SNAPSHOTID}" 
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Compressing in QCOW2 the downloaded VM ${_VMNAME} snapshot ...\t\t"
qemu-img convert -c -q -f qcow2 -O qcow2 ./tmp ./${_NAME} || exit_for_error "Error Compressing the Image" false hard "rm -fr ./tmp ./${_NAME} ; glance image-delete ${_SNAPSHOTID}"
echo -e "${GREEN} [OK]${NC}"


echo -e -n " - Clean Up phase 1 ...\t\t"
glance image-delete ${_SNAPSHOTID}
rm -f ./tmp
echo -e "${GREEN} [OK]${NC}"

bash Tools/ImageLoader.sh --env ${_ENVFOLDER} -i ./${_NAME} -n ${_NAME}

echo -e -n " - Clean Up phase 2 ...\t\t"
rm -rf ./${_NAME}
echo -e "${GREEN} [OK]${NC}"


exit 0
