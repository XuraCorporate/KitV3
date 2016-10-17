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
			echo "Help for Pre Validation phase"
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

echo -e "${GREEN}Pre-Validation${NC}"
_OPENSTACKRC="${_ENVFOLDER}/OpenStackRC/openstackrc"

ls "${_OPENSTACKRC}" >/dev/null 2>&1 || exit_for_error "Environment path is not valid ${_ENVFOLDER}" false hard

echo -e -n " - Verifying dos2unix binary ...\t\t\t\t\t\t"
which dos2unix > /dev/null 2>&1 || exit_for_error "Error, Cannot find dos2unix binary, please install it." false hard
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Verifying md5sum binary ...\t\t\t\t\t\t\t"
which md5sum > /dev/null 2>&1 || exit_for_error "Error, Cannot find md5sum binary, please install it" false hard
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Verifying qemu-img binary ...\t\t\t\t\t\t"
which qemu-img > /dev/null 2>&1 || exit_for_error "Error, Cannot find qemu-img binary, please install the qemu-utils" false hard
echo -e "${GREEN} [OK]${NC}"

#####
# Convert every files
#####
echo -e -n " - Eventually converting files in Standard Unix format ...\t\t\t"
for _FILE in $(find . -not \( -path ./.git -prune \) -type f)
do
        _MD5BEFORE=$(md5sum ${_FILE}|awk '{print $1}')
        dos2unix ${_FILE} >/dev/null 2>&1
        _MD5AFTER=$(md5sum ${_FILE}|awk '{print $1}')
        #####
        # Verify the MD5 after and before the dos2unix - eventually commit the changes
        #####
done
echo -e "${GREEN} [OK]${NC}"

#####
# Verify if there is the environment file
#####
echo -e -n " - Verifying environment file ...\t\t\t\t\t\t"
_ENV="${_ENVFOLDER}/common.yaml"
if [ ! -f ${_ENV} ] || [ ! -r ${_ENV} ] || [ ! -s ${_ENV} ]
then
        exit_for_error "Error, Environment file is missing." false hard
fi
echo -e "${GREEN} [OK]${NC}"

#####
# Verify if there is the environment check file
#####
echo -e -n " - Verifying environment file unit tests ...\t\t\t\t\t"
_CHECKS="${_ENVFOLDER}/common_checks"
if [ ! -f ${_CHECKS} ] || [ ! -r ${_CHECKS} ] || [ ! -s ${_CHECKS} ]
then
        exit_for_error "Error, Environment Check file is missing." false hard
fi
echo -e "${GREEN} [OK]${NC}"

#####
# Verify if there is any duplicated entry in the environment file
#####
echo -e -n " - Verifying duplicate entries in the environment file ...\t\t\t"
_DUPENTRY=$(cat ${_ENV}|grep -v -E '^[[:space:]]*$|^$'|awk '{print $1}'|grep -v "#"|sort|uniq -c|grep " 2 "|wc -l)
if (( "${_DUPENTRY}" > "0" ))
then
        echo -e "${RED}Found Duplicate Entries in the environment file${NC}"
        _OLDIFS=$IFS
        IFS=$'\n'
        for _VALUE in $(cat ${_ENV}|grep -v -E '^[[:space:]]*$|^$'|awk '{print $1}'|grep -v "#"|sort|uniq -c|grep " 2 "|awk '{print $2}'|sed 's/://g')
        do
                echo -e "${YELLOW}This parameters is present more than once:${NC} ${RED}${_VALUE}${NC}"
        done
        IFS=${_OLDIFS}
        exit_for_error "Error, Please fix the above duplicate entries and then you can continue." false hard
fi
echo -e "${GREEN} [OK]${NC}"

#####
# Verify if there is a test for each entry in the environment file
#####
echo -e -n " - Verifying if there is a test for each entry in the environment file ...\t"
_EXIT=false
_OLDIFS=$IFS
IFS=$'\n'
for _ENVVALUE in $(cat ${_ENV}|grep -v -E '^[[:space:]]*$|^$'|grep -v -E "parameter_defaults|[-]{3}"|awk '{print $1}'|grep -v "#")
do
        grep ${_ENVVALUE} ${_CHECKS} >/dev/null 2>&1
        if [[ "${?}" != "0" ]]
        then
                _EXIT=true
                echo -e -n "\n${YELLOW}Error, missing test for parameter ${NC}${RED}${_ENVVALUE}${NC}${YELLOW} in environment check file ${_CHECKS}${NC}"
        fi
done
if ${_EXIT}
then
        echo -e -n "\n"
        exit 1
fi
IFS=${_OLDIFS}
echo -e "${GREEN} [OK]${NC}"

#####
# Verify if the environment file has the right input values
#####
echo -e -n " - Verifying if the environment file has all of the right input values ...\t"
_EXIT=false
_OLDIFS=$IFS
IFS=$'\n'
for _INPUTTOBECHECKED in $(cat ${_CHECKS})
do
        _PARAM=$(echo ${_INPUTTOBECHECKED}|awk '{print $1}')
        _EXPECTEDVALUE=$(echo ${_INPUTTOBECHECKED}|awk '{print $2}')
        _PARAMFOUND=$(grep ${_PARAM} ${_ENV}|awk '{print $1}')
        _VALUEFOUND=$(grep ${_PARAM} ${_ENV}|awk '{print $2}'|sed "s/\"//g")
        #####
        # Verify that I have all of my parameters
        #####
        if [[ "${_PARAMFOUND}" == "" ]]
        then
                _EXIT=true
                echo -e -n "\n${YELLOW}Error, missing parameter ${NC}${RED}${_PARAM}${NC}${YELLOW} in environment file.${NC}"
        fi
        #####
        # Verify that I have for each parameter a value
        #####
        if [[ "${_VALUEFOUND}" == "" && "${_PARAMFOUND}" != "" ]]
        then
                _EXIT=true
                echo -e -n "\n${YELLOW}Error, missing value for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file.${NC}"
        fi
        #####
        # Verify that I have the right/expected value
        #####
        if [[ "${_EXPECTEDVALUE}" == "string" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "[a-zA-Z_-\.]" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be a String with the following characters a-zA-Z_-.${NC}"
                fi
        elif [[ "${_EXPECTEDVALUE}" == "boolean" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "^(true|false|True|False|TRUE|FALSE)$" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be a Boolean, e.g. True${NC}"
                fi
        elif [[ "${_EXPECTEDVALUE}" == "number" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "[0-9]" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be a Number, e.g. 123${NC}"
                fi
        elif [[ "${_EXPECTEDVALUE}" == "string|number" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "[a-zA-Z_-\.0-9]" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be either a Number or a String, e.g. 1${NC}"
                fi
        elif [[ "${_EXPECTEDVALUE}" == "ip" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be an IP Address, e.g. 192.168.1.1 or a NetMask e.g. 255.255.255.0 or a Network Cidr, e.g. 192.168.1.0/24${NC}"
                fi
        elif [[ "${_EXPECTEDVALUE}" == "vlan" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "^(none|[0-9]{1,4})$" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be a VLAN ID, between 1 to 4096 or none in case of diabled VLAN configuration${NC}"
                fi
        elif [[ "${_EXPECTEDVALUE}" == "anti-affinity|affinity" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "^(anti-affinity|affinity)$" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be \"anti-affinity\" or \"affinity\"${NC}"
                fi
        elif [[ "${_EXPECTEDVALUE}" == "glance|cinder" ]]
        then
                echo "${_VALUEFOUND}"|grep -E "^(glance|cinder)$" >/dev/null 2>&1
                if [[ "${?}" != "0" ]]
                then
                        _EXIT=true
                        echo -e -n "\n${YELLOW}Error, value ${NC}${RED}${_VALUEFOUND}${NC}${YELLOW} for parameter ${NC}${RED}${_PARAMFOUND}${NC}${YELLOW} in environment file is not correct.${NC}"
                        echo -e -n "\n${RED}It has to be \"glance\" or \"cinder\"${NC}"
                fi
        else
                _EXIT=true
                echo -e -n "\n${YELLOW}Error, Expected value to check ${NC}${RED}${_EXPECTEDVALUE}${NC}${YELLOW} is not correct.${NC}"
        fi
done
if ${_EXIT}
then
        echo -e -n "\n"
        exit 1
fi
IFS=${_OLDIFS}
echo -e "${GREEN} [OK]${NC}"

#####
# Verify binary
#####
echo -e "\n${GREEN}${BOLD}Verifying OpenStack Binaries${NC}${NORMAL}"
_BINS="nova glance cinder neutron heat"
for _BIN in ${_BINS}
do
        echo -e -n " - Verifying ${_BIN} binary ...\t\t"
        which ${_BIN} > /dev/null 2>&1 || exit_for_error "Error, Cannot find python${_BIN}-client." false hard
        echo -e "${GREEN} [OK]${NC}"
done

echo -e -n " - Verifying Heat Assume Yes ...\t"
_ASSUMEYES=""
heat help stack-delete|grep "\-\-yes" >/dev/null 2>&1
if [[ "${?}" == "0" ]]
then
        _ASSUMEYES="--yes"
        echo -e "${GREEN} [OK]${NC}"
else
        echo -e "${YELLOW} [NOT AVAILABLE]${NC}"
fi

echo -e "\n${GREEN}${BOLD}Verifying OpenStack Credential Authentication${NC}${NORMAL}"
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
echo -e -n " - Loading environment file ...\t\t"
source ${_OPENSTACKRC}
echo -e "${GREEN} [OK]${NC}"

#####
# Verify if the given credential are valid. This will also check if the use can contact Heat
#####
echo -e -n " - Verifying OpenStack credential ...\t"
nova --timeout 5 endpoints > /dev/null 2>&1 || exit_for_error "Error, During credential validation." false hard
echo -e "${GREEN} [OK]${NC}"

echo -e "\n${GREEN}${BOLD}Verifying OpenStack API Access${NC}${NORMAL}"
echo -e -n " - Verifying access to OpenStack Nova API ...\t\t"
nova list > /dev/null 2>&1 || exit_for_error "Error, During credential validation." false hard
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Verifying access to OpenStack Glance API ...\t\t"
glance image-list > /dev/null 2>&1 || exit_for_error "Error, During credential validation." false hard
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Verifying access to OpenStack Cinder API ...\t\t"
cinder list > /dev/null 2>&1 || exit_for_error "Error, During credential validation." false hard
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Verifying access to OpenStack Neutron API ...\t"
neutron net-list > /dev/null 2>&1 || exit_for_error "Error, During credential validation." false hard
echo -e "${GREEN} [OK]${NC}"

echo -e -n " - Verifying access to OpenStack Heat API ...\t\t"
heat stack-list > /dev/null 2>&1 || exit_for_error "Error, During credential validation." false hard
echo -e "${GREEN} [OK]${NC}"

exit 0
