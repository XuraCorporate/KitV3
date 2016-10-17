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

echo -e "\n${GREEN}${BOLD}Verifying Units Flavors${NC}${NORMAL}"
for _UNITTOBEVALIDATED in "cms" "dsu" "lvu" "mau" "omu" "smu" "vm-asu"
do
        _FLAVOR=$(cat ${_ENV}|awk '/'$(echo "${_UNITTOBEVALIDATED}" | awk '{print tolower($0)}')_flavor_name'/ {print $2}'|sed "s/\"//g")

        #####
        # Check the given flavor is available
        #####
        echo -e -n " - Validating chosen Flavor ${_FLAVOR} for Unit ${_UNITTOBEVALIDATED} ...\t\t\t\t\t"
        nova flavor-show "${_FLAVOR}" >/dev/null 2>&1 || exit_for_error "Error, Flavor for Unit ${_UNITTOBEVALIDATED} not present." true hard
        echo -e "${GREEN} [OK]${NC}"
done

exit 0
