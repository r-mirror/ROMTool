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
    [[ -e "build/envsetup.sh" ]] || err "Error: Must run from root of repo"

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

checkPath() {
    # Checking file build/envsetup.sh
    if [ ! -e "build/envsetup.sh" ]; then
        err "Error: Must run from root of repo"
    fi

    # Checking file project.list, if false run doInit
    [[ -f $LIST ]] || doInit #err "Error: File project.list not found, please do init first"
}

doList() {
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

changeBranchManifest() {
    local XML="$CWD/manifest/snippets/aheads.xml"
    local OLD=$1
    local NEW=$2

    # Specific line 6 only to be replace
    sed -i "6s|$OLD|$NEW|" $XML

    git -C "$CWD/manifest" commit -a -m "manifest: Changed branch to $NEW for testing" || return 1
}

doRebase() {
    local PROJECTPATHS=$(cat $LIST)
    local BRANCH=$1
    local TAG=$2
    local NEWBRANCH="${BRANCH}-rebase-${TAG}"

    # Make sure manifest and forked repos are in a consistent state
    prin "#### Verifying there are no uncommitted changes on forked AOSP projects ####"
    for i in ${PROJECTPATHS} .repo/manifests; do
        # cd "${CWD}/${PROJECTPATH}"
        if [[ -n "$(git -C "$CWD/$i" status --porcelain)" ]]; then
            err "Path ${i} has uncommitted changes. Please fix."
        fi
    done
    grn "#### Verification complete - no uncommitted changes found ####"

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
            blu "Rebasaing $PROJECTPATH"
            if  ! git -C "$CWD/$PROJECTPATH" checkout "${BRANCH}" &> /dev/null
            then
                red "Error: Failed checkout repo $PROJECTPATH to branch $BRANCH, please check again. Continue to next repo"
                continue
            fi
            if ! git -C "$CWD/$PROJECTPATH" fetch -q $repo_url $TAG
            then
                red "Error: Failed fetching repo $PROJECTPATH, please check connection. Continue to next repo"
                continue
            fi
            git -C "$CWD/$PROJECTPATH" branch -D "$NEWBRANCH" &> /dev/null
            git -C "$CWD/$PROJECTPATH" checkout -b "$NEWBRANCH" &> /dev/null
            if git -C "$CWD/$PROJECTPATH" rebase FETCH_HEAD &> /dev/null; then
                if [[ $(git -C "$CWD/$PROJECTPATH" rev-parse HEAD) != $(git -C "$CWD/$PROJECTPATH" rev-parse $REMOTE/$BRANCH) ]] && [[ $(git -C "$CWD/$PROJECTPATH" diff HEAD $REMOTE/$BRANCH) ]]; then
                    echo "$PROJECTPATH" >> $CWD/success.list
                    grn "Rebase $PROJECTPATH success"
                else
                    prin "$PROJECTPATH - unchanged"
                    git -C "$CWD/$PROJECTPATH" checkout "${BRANCH}" &> /dev/null
                    git -C "$CWD/$PROJECTPATH" branch -D "$NEWBRANCH" &> /dev/null
                fi
            else
                echo "$PROJECTPATH" >> $CWD/failed.list
                red "$REPO Rebasing failed"
            fi
        else
            red "Failed fetching, please check connection"
        fi
    done

    prin
    grn "These repos success rebasaing:"
    cat "$CWD/success.list"
    red "These repos success rebasaing:"
    cat "$CWD/failed.list"

    if [[ -f "$CWD/manifest/snippets/bianca.xml" ]]
    then
        dbg "Detected Bianca Project XML. Trying to change branch with new rebased branch"
        changeBranchManifest "$BRANCH" "$NEWBRANCH"
    fi 
}

doStart() {
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
    local REMOTE=$1
    local BRANCH=$2

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Fetching repo $1 with branch $BRANCH"

        if ! git -C "$CWD/$1" fetch -q $REMOTE $BRANCH
        then
            red "Failed fetching repo $1"
            prin
            continue
        fi

        grn "Success"
        prin

    done
}

doPush() {
    local REMOTE=$1
    local BRANCH=$2
    local CUSTOM=$3

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Push repo $1 with branch $BRANCH"

        if ! git -C "$CWD/$1" push $CUSTOM $REMOTE $BRANCH
        then
            red "Failed push repo $1"
            prin
            continue
        fi

        grn "Success"
        prin

    done
}

doCheckout() {
    local BRANCH=$1

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Checkouting repo $1 to $BRANCH"

        if ! git -C "$CWD/$1" checkout $BRANCH &> /dev/null
        then
            red "Failed checkout repo $1"
            prin
            continue
        fi

        grn "Success"
        prin

    done
}

doReset() {
    local BRANCH=$1

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Reset-hard repo $1 to $BRANCH"

        if ! git -C "$CWD/$1" reset --hard $BRANCH &> /dev/null
        then
            red "Failed reset-hard repo $1"
            prin
            continue
        fi

        grn "Success"
        prin

    done
}

usage() {
    prin "Usage: $(basename $0) <command> [<argument>]"
    prin
    prin "Command:"
    prin "  init                                Initial with creating project.list"
    prin "  list                                Listing project.list"
    prin "  start <branch>                      Creating new branch"
    prin "  checkout <branch>                   Checkout all repo with already branch"
    prin "  fetch <remote> <branch>             Fetching all repo"
    prin "  reset-hard <branch>                 Reseting hard"
    prin "  rebase <currentbranch> <aosptag>    Rebase all repo with new aosp tag"
    prin "  push <remote> <branch>              Push all repo"
    prin "  push-force <remote> <branch>        Push all repo with flag --force"
    prin "  push-delete <remote> <branch>        Push all repo with flag --force"
    prin "  help                                Print usage"
    prin
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "${1}" in
        init)
            doInit
            exit
            ;;
        start)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doStart "$2"
                shift
            else
                err "Error: Argument for $1 is missing or more/less than 1 argument. Command: start <branch>"
            fi
            exit
            ;;
        list)
            checkPath
            doList
            exit
            ;;
        rebase)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doRebase "$2" "$3"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: rebase <currentbranch> <aospnewtag>"
            fi
            exit
            ;;
        fetch)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doFetch "$2" "$3"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: fetch <remote> <branch>"
            fi
            exit
            ;;
        push)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doPush "$2" "$3"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: push <remote> <branch>"
            fi
            exit
            ;;
        push-force)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doPush "$2" "$3" "--force"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: push-force <remote> <branch>"
            fi
            exit
            ;;
        push-delete)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doPush "$2" "$3" "--delete"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: push-delete <remote> <branch>"
            fi
            exit
            ;;
        checkout)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doCheckout "$2"
                shift
            else
                err "Error: Argument for $1 is missing or more/less than 1 argument. Command: checkout <branch>"
            fi
            exit
            ;;
        reset-hard)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doReset "$2"
                shift
            else
                err "Error: Argument for $1 is missing or more/less than 1 argument. Command: reset-hard <branch>"
            fi
            exit
            ;;
        help|*)
            usage
            exit
            ;;
    esac
    shift
done