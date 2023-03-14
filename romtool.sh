#!/usr/bin/env bash

# Copyright (C) BiancaProject
# Copyright (C) 2019-2023 alanndz <alanmahmud0@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later

NAME="ROMTool"
VERSION="1.0"
CWD=$(pwd)

dbg() { echo -e "\e[92m[*] $@\e[39m"; }
err() { echo -e "\e[91m[!] $@\e[39m"; exit 1; }
grn() { echo -e "\e[92m$@\e[39m"; }
red() { echo -e "\e[91m$@\e[39m"; }
prin() { echo -e "$@"; }

# Checking dependencies
for dep in git env basename mkdir rm repo
do
   ! command -v "$dep" &> /dev/null && err "Unable to locate dependency $dep. Exiting."
done

CONF="$cwd/.romtoolconfig"

##### Setup Config #####
Config.xml() { git config -f "$CONF" rom.xml "$@"; }
Config.remote() { git config -f "$CONF" rom.remote "$@"; }

# Environment default for BiancaProject
LIST="${CWD}/project.list"
BLACKLIST=$(cat "${CWD}/scripts/blacklist")
MANIFEST=$(Config.xml)
REMOTE=$(Config.remote)
MANIFEST="${MANIFEST:-$CWD/.repo/manifests/snippets/bianca.xml}"
REMOTE="${REMOTE:-dudu}"
    
doInit() {
    dbg "Info: Creating project.list"

    # Build list of Bianca Project forked repos
    local PROJECTPATHS=$(grep "remote=\"${REMOTE}" "${MANIFEST}" | sed -n 's/.*path="\([^"]\+\)".*/\1/p')

    for PROJECTPATH in ${PROJECTPATHS}; do
        if [[ "${BLACKLIST}" =~ "${PROJECTPATH}" ]]; then
            continue
        fi

        echo "${PROJECTPATH}"
    done | sort > "${LIST}"

}

doList() {
    prin "TODO"
}

doRebase() {
    prin "TODO"
}

doStart() {
    prin "TODO"
}

#if [ ! -e "build/envsetup.sh" ]; then
#    echo "Error: Must run from root of repo"
#fi

# Parse options
END_OF_OPT=
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "${END_OF_OPT}${1}" in
        init)
            doInit
            exit
            ;;
        start)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                doStart "$2"
                shift
            else
                err "Error: Argument for $1 is missing or more/less than 1 argument"
            fi
            exit
            ;;
        --)
            END_OF_OPT=1 ;;
        *)
            POSITIONAL+=("$1") ;;
    esac
    shift
done

# Restore positional parameters
set -- "${POSITIONAL[@]}"