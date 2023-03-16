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
blu() { echo -e "\e[34m$@\e[39m"; }
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
AOSP="https://android.googlesource.com"
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
    [[ -f $LIST ]] || err "Error: File project.list not found, please do init first"

    local PROJECTPATH=()
    local CURRENTBRANCH=()
    local REPO=($(cat $LIST))

    for i in "${REPO[@]}"
    do
        PROJECTPATH+=("$i")
        CURRENTBRANCH+=("$(git -C "$CWD/$i" branch --show-current || echo " ")")
    done

    paste <(printf '%s\n' `blu Repo` "${PROJECTPATH[@]}") \
        <(printf '%s\n' `blu Branch` "${CURRENTBRANCH[@]}") \
        | column -ts $'\t'

}
doRebase() {
    [[ -f $LIST ]] || err "Error: File project.list not found, please do init first"

    local PROJECTPATHS=$(cat $LIST)
    local BRANCH=$1
    local TAG=$2

    # Make sure manifest and forked repos are in a consistent state
    prin "#### Verifying there are no uncommitted changes on forked AOSP projects ####"
    for i in ${PROJECTPATHS} .repo/manifests; do
        # cd "${CWD}/${PROJECTPATH}"
        if [[ -n "$(git -C "$CWD/$i" status --porcelain)" ]]; then
            err "Path ${i} has uncommitted changes. Please fix."
        fi
    done
    prin "#### Verification complete - no uncommitted changes found ####"

    for files in success.list failed.list
    do
        rm $CWD/$files 2> /dev/null
        touch $CWD/$files
    done

    for PROJECTPATH in ${PROJECTPATHS}; do
        if [[ "${BLACKLIST}" =~ "${PROJECTPATH}" ]]; then
            continue
        fi

        case $PROJECTPATH in
            build/make) repo_url="$AOSP/platform/build" ;;
            *) repo_url="$AOSP/platform/$PROJECTPATH" ;;
        esac

        if wget -q --spider $repo_url; then
            prin "`blu Rebasaing $PROJECTPATH`"
            git -C "$CWD/$PROJECTPATH" checkout "${BRANCH}" &> /dev/null || red "Error: Failed checkout repo $PROJECTPATH to branch $BRANCH, please check again. Continue to next repo"; prin; continue
            prin 
            git -C "$CWD/$PROJECTPATH" fetch -q $repo_url $TAG &> /dev/null || red "Error: Failed fetching repo $PROJECTPATH, please check connection. Continue to next repo"; prin; continue
            git -C "$CWD/$PROJECTPATH" branch -D "${BRANCH}-rebase-${TAG}" &> /dev/null
            git -C "$CWD/$PROJECTPATH" checkout -b "${BRANCH}-rebase-${TAG}" &> /dev/null
            if git -C "$CWD/$PROJECTPATH" rebase FETCH_HEAD &> /dev/null; then
                if [[ $(git -C "$CWD/$PROJECTPATH" rev-parse HEAD) != $(git -C "$CWD/$PROJECTPATH" rev-parse $REMOTE/$BRANCH) ]] && [[ $(git -C "$CWD/$PROJECTPATH" diff HEAD $REMOTE/$BRANCH) ]]; then
                    echo "$PROJECTPATH" >> $CWD/success.list
                    prin "`grn Rebase $PROJECTPATH success`"
                else
                    prin "$PROJECTPATH - unchanged"
                    git -C "$CWD/$PROJECTPATH" checkout "${BRANCH}" &> /dev/null
                    git -C "$CWD/$PROJECTPATH" branch -D "${BRANCH}-rebase-${TAG}" &> /dev/null
                fi
            else
                echo "$PROJECTPATH" >> $CWD/failed.list
                prin "`red $REPO Rebasing failed`"
            fi
            # cd "${TOP}"
        else
            prin "`red Failed fetching, please check connection`"
        fi
    done

    prin
    prin "`grn These repos success rebasaing:`"
    cat success.list
    prin "`red These repos success rebasaing:`"
    cat failed.list
}

doStart() {
    [[ -f $LIST ]] || doInit

    BRANCH=$1

    cat "${LIST}" | while read l; do
        set ${l}
        PROJECTPATH="${1}"

        if [ ! -d "${PROJECTPATH}" ]; then continue; fi

        prin "Starting repo $PROJECTPATH to $BRANCH"
        prin

        repo start "${BRANCH}" "${PROJECTPATH}" || red "Failed start repo $PROJECTPATH"

    done

    dbg "Info: Success start repo to $BRANCH"
}

doFetch() {
    [[ -f $LIST ]] || err "Error: File project.list not found, please do init first"

    local REMOTE=$1
    local BRANCH=$2

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Fetching repo $1 with branch $BRANCH"

        if ! git -C "$CWD/$1" fetch -q $REMOTE $BRANCH
        then
            red "Failed fetching repo $1"
            continue
        fi

        grn "Success"

    done
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
                err "Error: Argument for $1 is missing or more/less than 1 argument. Command: start <branch>"
            fi
            exit
            ;;
        list)
            doList
            exit
            ;;
        rebase)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                doRebase "$2" "$3"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: rebase <currentbranch> <aospnewtag>"
            fi
            exit
            ;;
        fetch)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                doFetch "$2" "$3"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: fetch <remote> <branch>"
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