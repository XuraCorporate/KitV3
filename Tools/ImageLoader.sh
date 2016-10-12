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
	    		_IMAGEFOLDER="$2"
	    		shift
	    		;;
		-h|--help)
			echo "Help for Image Loader Script"
			echo "-e|--env <envirnment folder - e.g Environments/Dev_environment>"
			echo "-i|--image <image folder - e.g Images/Dev>"
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

if [[ "${_IMAGEFOLDER}" == "" ]]
then
	exit_for_error "Missing Image Folder path" false hard
else
	ls "${_IMAGEFOLDER}" >/dev/null 2>&1 || exit_for_error "Image path is not valid" false hard
	if [[ "$(ls ${_IMAGEFOLDER})" == "" ]]
	then
		exit_for_error "Image path is empty" false hard
	fi
	if [[ "$(find ${_IMAGEFOLDER} -type d -not -path ${_IMAGEFOLDER})" != "" ]]
	then
		exit_for_error "Image path has subdirectory" false hard
	fi
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

for _IMAGE in $(ls ${_IMAGEFOLDER})
do
	_IMAGEMD5=$(md5sum ${_IMAGEFOLDER}/${_IMAGE}|awk '{print $1}')
	#TODO - Support multiple image type using file or qemu-img info
	_IMAGENAME=$(echo ${_IMAGE}|sed -e "s/\.qcow2//g" -e "s/\.img//g" -e "s/\.iso//g")
	_IMAGEEXIST=$(glance image-show $(glance image-list|awk '/ '${_IMAGENAME}' / {print $2}') 2>/dev/null)
	# Try to avoid to load two images with the same name
	if [[ "$(echo "${_IMAGEEXIST}"|awk '/ checksum / {print $4}')" != "${_IMAGEMD5}" ]]
	then
		_IMAGEOUTPUT=$(glance image-create \
			--file ${_IMAGEFOLDER}/${_IMAGE} \
			--name ${_IMAGENAME} \
			--disk-format qcow2 \
			--container-format bare || exit_for_error "Error upload image - ${_IMAGE}" false hard) >/dev/null 2>&1
		if [[ "$(echo "${_IMAGEOUTPUT}"|awk '/ checksum / {print $4}')" != "${_IMAGEMD5}" ]]
		then
			exit_for_error "Error validating the image ${_IMAGE} checksum"
		fi
	fi
done
exit 0
