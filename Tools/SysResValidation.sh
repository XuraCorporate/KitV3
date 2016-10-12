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

_CMSFLAVOR=$(cat ${_ENV}|awk '/cms_flavor_name/ {print $2}'|sed "s/\"//g")
_CMSFLAVOROUTPUT=$(nova flavor-show ${_CMSFLAVOR})
_CMSVCPU=$(echo "${_CMSFLAVOROUTPUT}"|grep " vcpus "|awk '{print $4}')
_CMSVRAM=$(echo "${_CMSFLAVOROUTPUT}"|grep " ram "|awk '{print $4}')
_CMSVDISK=$(echo "${_CMSFLAVOROUTPUT}"|grep " disk "|awk '{print $4}')
_CMSUNITS=$(cat ${_ENVFOLDER}/cms/admin.csv|wc -l)

_DSUFLAVOR=$(cat ${_ENV}|awk '/dsu_flavor_name/ {print $2}'|sed "s/\"//g")
if [[ "${_DSUFLAVOR}" == "${_CMSFLAVOR}" ]]
then
        _DSUFLAVOROUTPUT=${_CMSFLAVOROUTPUT}
else
        _DSUFLAVOROUTPUT=$(nova flavor-show ${_DSUFLAVOR})
fi
_DSUVCPU=$(echo "${_DSUFLAVOROUTPUT}"|grep " vcpus "|awk '{print $4}')
_DSUVRAM=$(echo "${_DSUFLAVOROUTPUT}"|grep " ram "|awk '{print $4}')
_DSUVDISK=$(echo "${_DSUFLAVOROUTPUT}"|grep " disk "|awk '{print $4}')
_DSUUNITS=$(cat ${_ENVFOLDER}/dsu/admin.csv|wc -l)

_LVUFLAVOR=$(cat ${_ENV}|awk '/lvu_flavor_name/ {print $2}'|sed "s/\"//g")
if [[ "${_LVUFLAVOR}" == "${_DSUFLAVOR}" ]]
then
        _LVUFLAVOROUTPUT=${_DSUFLAVOROUTPUT}
else
        _LVUFLAVOROUTPUT=$(nova flavor-show ${_LVUFLAVOR})
fi
_LVUVCPU=$(echo "${_LVUFLAVOROUTPUT}"|grep " vcpus "|awk '{print $4}')
_LVUVRAM=$(echo "${_LVUFLAVOROUTPUT}"|grep " ram "|awk '{print $4}')
_LVUVDISK=$(echo "${_LVUFLAVOROUTPUT}"|grep " disk "|awk '{print $4}')
_LVUUNITS=$(cat ${_ENVFOLDER}/lvu/admin.csv|wc -l)

_MAUFLAVOR=$(cat ${_ENV}|awk '/mau_flavor_name/ {print $2}'|sed "s/\"//g")
if [[ "${_MAUFLAVOR}" == "${_LVUFLAVOR}" ]]
then
        _MAUFLAVOROUTPUT=${_LVUFLAVOROUTPUT}
else
        _MAUFLAVOROUTPUT=$(nova flavor-show ${_MAUFLAVOR})
fi
_MAUVCPU=$(echo "${_MAUFLAVOROUTPUT}"|grep " vcpus "|awk '{print $4}')
_MAUVRAM=$(echo "${_MAUFLAVOROUTPUT}"|grep " ram "|awk '{print $4}')
_MAUVDISK=$(echo "${_MAUFLAVOROUTPUT}"|grep " disk "|awk '{print $4}')
_MAUUNITS=$(cat ${_ENVFOLDER}/mau/admin.csv|wc -l)

_OMUFLAVOR=$(cat ${_ENV}|awk '/omu_flavor_name/ {print $2}'|sed "s/\"//g")
if [[ "${_OMUFLAVOR}" == "${_MAUFLAVOR}" ]]
then
        _OMUFLAVOROUTPUT=${_MAUFLAVOROUTPUT}
else
        _OMUFLAVOROUTPUT=$(nova flavor-show ${_OMUFLAVOR})
fi
_OMUVCPU=$(echo "${_OMUFLAVOROUTPUT}"|grep " vcpus "|awk '{print $4}')
_OMUVRAM=$(echo "${_OMUFLAVOROUTPUT}"|grep " ram "|awk '{print $4}')
_OMUVDISK=$(echo "${_OMUFLAVOROUTPUT}"|grep " disk "|awk '{print $4}')
_OMUUNITS=$(cat ${_ENVFOLDER}/omu/admin.csv|wc -l)

_SMUFLAVOR=$(cat ${_ENV}|awk '/smu_flavor_name/ {print $2}'|sed "s/\"//g")
if [[ "${_SMUFLAVOR}" == "${_OMUFLAVOR}" ]]
then
        _SMUFLAVOROUTPUT=${_OMUFLAVOROUTPUT}
else
        _SMUFLAVOROUTPUT=$(nova flavor-show ${_SMUFLAVOR})
fi
_SMUVCPU=$(echo "${_SMUFLAVOROUTPUT}"|grep " vcpus "|awk '{print $4}')
_SMUVRAM=$(echo "${_SMUFLAVOROUTPUT}"|grep " ram "|awk '{print $4}')
_SMUVDISK=$(echo "${_SMUFLAVOROUTPUT}"|grep " disk "|awk '{print $4}')
_SMUUNITS=$(cat ${_ENVFOLDER}/smu/admin.csv|wc -l)

_VMASUFLAVOR=$(cat ${_ENV}|awk '/vm-asu_flavor_name/ {print $2}'|sed "s/\"//g")
if [[ "${_VMASUFLAVOR}" == "${_SMUFLAVOR}" ]]
then
        _VMASUFLAVOROUTPUT=${_SMUFLAVOROUTPUT}
else
        _VMASUFLAVOROUTPUT=$(nova flavor-show ${_VMASUFLAVOR})
fi
_VMASUVCPU=$(echo "${_VMASUFLAVOROUTPUT}"|grep " vcpus "|awk '{print $4}')
_VMASUVRAM=$(echo "${_VMASUFLAVOROUTPUT}"|grep " ram "|awk '{print $4}')
_VMASUVDISK=$(echo "${_VMASUFLAVOROUTPUT}"|grep " disk "|awk '{print $4}')
_VMASUUNITS=$(cat ${_ENVFOLDER}/vm-asu/admin.csv|wc -l)

_TENANTQUOTA=$(nova quota-show)
_TENANTVCPU=$(echo "${_TENANTQUOTA}"|awk '/\| cores / {print $4}')
_TENANTVRAM=$(echo "${_TENANTQUOTA}"|awk '/\| ram / {print $4}')
_TENANTVDISK=$(echo "${_TENANTQUOTA}"|awk '/\| disk / {print $4}')
_TENANTVMS=$(echo "${_TENANTQUOTA}"|awk '/\| instances / {print $4}')

_NEEDEDVCPU=$(( (${_CMSVCPU} * ${_CMSUNITS}) + (${_DSUVCPU} * ${_DSUUNITS}) + (${_LVUVCPU} * ${_LVUUNITS}) + (${_MAUVCPU} * ${_MAUUNITS}) + (${_OMUVCPU} * ${_OMUUNITS}) + (${_SMUVCPU} * ${_SMUUNITS}) + (${_VMASUVCPU} * ${_VMASUUNITS}) ))
_NEEDEDVRAM=$(( (${_CMSVRAM} * ${_CMSUNITS}) + (${_DSUVRAM} * ${_DSUUNITS}) + (${_LVUVRAM} * ${_LVUUNITS}) + (${_MAUVRAM} * ${_MAUUNITS}) + (${_OMUVRAM} * ${_OMUUNITS}) + (${_SMUVRAM} * ${_SMUUNITS}) + (${_VMASUVRAM} * ${_VMASUUNITS}) ))
_NEEDEDVDISK=$(( (${_CMSVDISK} * ${_CMSUNITS}) + (${_DSUVDISK} * ${_DSUUNITS}) + (${_LVUVDISK} * ${_LVUUNITS}) + (${_MAUVDISK} * ${_MAUUNITS}) + (${_OMUVDISK} * ${_OMUUNITS}) + (${_SMUVDISK} * ${_SMUUNITS}) + (${_VMASUVDISK} * ${_VMASUUNITS}) ))
_NEEDEDUNITS=$(( ${_CMSUNITS} + ${_DSUUNITS} + ${_LVUUNITS} + ${_MAUUNITS} + ${_OMUUNITS} + ${_SMUUNITS} + ${_VMASUUNITS} ))

if (( ${_NEEDEDVCPU} > ${_TENANTVCPU} )) && [[ ${_TENANTVCPU} != "-1" ]]
then
        echo -e "${RED}The Tenant Quota has ${_TENANTVCPU} vCPU and you are going to use ${_NEEDEDVCPU}${NC}"
fi

if (( ${_NEEDEDVRAM} > ${_TENANTVRAM} )) && [[ ${_TENANTVRAM} != "-1" ]]
then
        echo -e "${RED}The Tenant Quota has ${_TENANTVRAM} vRAM and you are going to use ${_NEEDEDVRAM}${NC}"
fi

if [[ "$(echo ${_TENANTVDISK}|grep -E -v "[0-9]")" == "" && "${_TENANTVDISK}" != "" ]]
then
        if (( ${_NEEDEDVDISK} > ${_TENANTVDISK} )) && [[ ${_TENANTVDISK} != "-1" ]]
        then
                echo -e "${RED}The Tenant Quota has ${_TENANTVDISK} vDISK and you are going to use ${_NEEDEDVDISK}${NC}"
        fi
fi

if (( ${_NEEDEDUNITS} > ${_TENANTVMS} )) && [[ ${_TENANTVMS} != "-1" ]]
then
        echo -e "${RED}The Tenant Quota has ${_TENANTVMS} Instance and you are going to create ${_NEEDEDUNITS}${NC}"
fi

#TODO
# QUOTA IS MISSING CURRENT ALLOCATED RESOURCES
# Ensure exit on error 


exit 0
