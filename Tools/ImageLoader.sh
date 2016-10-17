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
		-i|--image)
	    		_IMAGE="$2"
	    		shift
	    		;;
		-n|--name)
	    		_NAME="$2"
	    		shift
	    		;;
		-h|--help)
			echo "Help for Image Loader Script"
			echo "-e|--env <envirnment folder - e.g Environments/Dev_environment>"
			echo "-i|--image <image - e.g Images/Dev/swp-RedHat-Linux-OS-KVM.qcow2>"
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

if [[ "${_IMAGE}" == "" ]]
then
	exit_for_error "Missing Image path" false hard
else
	if [ ! -f ${_IMAGE} ] || [ ! -r ${_IMAGE} ] || [ ! -s ${_IMAGE} ]
	then
		exit_for_error "Image is not valid" false hard
	fi
fi
if [[ "${_NAME}" == "" ]]
then
        exit_for_error "Missing Image Name to be Used" false hard
fi

echo -e "${GREEN}Image Uploader${NC}"

#####
# Unload any previous loaded environment file
#####
for _BASHENV in $(env|grep ^OS|awk -F "=" '{print $1}')
do
        unset ${_BASHENV}
done

echo -e "${GREEN} [OK]${NC}"
#####
# Load environment file
#####
source ${_OPENSTACKRC}

echo -e -n " - Calculating Image ${_IMAGE} md5 ...\t\t"
_IMAGEMD5=$(md5sum ${_IMAGE}|awk '{print $1}')
echo -e "${GREEN} [OK]${NC}"

#TODO - Support multiple image type using file or qemu-img info
echo -e -n " - Verifying if image already exist ...\t\t"
_IMAGEEXIST=$(glance image-show $(glance image-list|awk '/ '${_NAME}' / {print $2}') 2>/dev/null)
echo -e "${GREEN} [OK]${NC}"

# Try to avoid to load two images with the same name
echo -e -n " - Comparing MD5s ...\t\t"
if [[ "$(echo "${_IMAGEEXIST}"|awk '/ checksum / {print $4}')" != "${_IMAGEMD5}" ]]
then
	echo -e "${GREEN} The image will be uploaded${NC}"
	_IMAGEOUTPUT=$(glance image-create \
		--file ${_IMAGE} \
		--name ${_NAME} \
		--disk-format qcow2 \
		--container-format bare || exit_for_error "Error upload image - ${_IMAGE}" false hard) >/dev/null 2>&1
	echo -e -n " - Verifying uploaded image MD5 with the local one ...\t\t"
	if [[ "$(echo "${_IMAGEOUTPUT}"|awk '/ checksum / {print $4}')" != "${_IMAGEMD5}" ]]
	then
		exit_for_error "Error validating the image ${_IMAGE} checksum" false hard "glance image-delete $(echo "${_IMAGEOUTPUT}"|awk '/ id / {print $4}')"
	fi
	echo -e "${GREEN} [OK]${NC}"
else
	echo -e "${GREEN} The image already exist, not uploaded.${NC}"
fi

exit 0
# TODO
# Name comes from outside 
# Add output in order to have task status
