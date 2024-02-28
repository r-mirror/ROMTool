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

CONF="$CWD/.romtoolconfig"

##### Setup Config #####
Config.xml() { git config -f "$CONF" rom.xml "$@"; }
Config.remote() { git config -f "$CONF" rom.remote "$@"; }

# Environment default for RevengeOS
AOSP="https://android.googlesource.com"
LIST="${CWD}/project.list"
BLACKLIST=$(cat "${CWD}/ROMTool/blacklist")
MANIFEST=$(Config.xml)
REMOTE=$(Config.remote)
MANIFEST="${MANIFEST:-$CWD/.repo/manifests/snippets/revengeos.xml}"
REMOTE="${REMOTE:-ros}"

doInit() {
    [[ -e "build/envsetup.sh" ]] || err "Error: Must run from root of repo"

    dbg "Info: Creating project.list"

    # Build list of RevengeOS forked repos
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
    local XML="$CWD/manifest/snippets/revengeos.xml"
    local NEW=$1
    local SC=($(cat $CWD/success.list))
    local FL=($(cat $CWD/failed.list))

    for i in ${SC[@]}
    do
        line=$(grep -n \"$i\" "$XML" | cut -d: -f 1)
        if [[ -n $line ]]
        then
            sed -i "${line}s|remote=\"ros\"|remote=\"ros\" revision=\"${NEW}\"|" "$XML"
        fi
    done

    for i in ${FL[@]}
    do
        line=$(grep -n \"$i\" "$XML" | cut -d: -f 1)
        git -C $i rev-parse --verify $NEW &> /dev/null || continue
        if [[ -n $line ]]
        then
            sed -i "${line}s|remote=\"ros\"|remote=\"ros\" revision=\"${NEW}\"|" "$XML"
        fi
    done

    git -C "$CWD/manifest" commit -a -m "[DNM]manifest: Track $NEW branch" || return 1
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
    prin

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

        if [[ "$PROJECTPATH" == "vendor/revengeos" ]]; then
            dbg "Detecting vendor/revengeos, checking out to $NEWBRANCH"
            git -C "$CWD/$PROJECTPATH" checkout -b "$NEWBRANCH" &> /dev/null
            echo "$PROJECTPATH" >> $CWD/success.list
            continue
        fi

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
                red "$PROJECTPATH Rebasing failed"
            fi
        else
            red "Failed checking url $repo_url, please check connection"
            echo "$PROJECTPATH" >> $CWD/failed.list
        fi
        prin
    done

    prin
    grn "These repos success rebasaing:"
    cat "$CWD/success.list"
    prin
    red "These repos failed rebasaing:"
    cat "$CWD/failed.list"
    prin

    if [[ -f "$CWD/manifest/snippets/revengeos.xml" ]]
    then
        dbg "Detected RevengeOS XML. Trying to change branch with new rebased branch"
        changeBranchManifest "$NEWBRANCH"
    fi 
}

doMerge() {
    local PROJECTPATHS=$(cat $LIST)
    local BRANCH=$1
    local TAG=$2
    local NEWBRANCH="${BRANCH}-merge-${TAG}"

    # Make sure manifest and forked repos are in a consistent state
    prin "#### Verifying there are no uncommitted changes on forked AOSP projects ####"
    for i in ${PROJECTPATHS} .repo/manifests; do
        # cd "${CWD}/${PROJECTPATH}"
        if [[ -n "$(git -C "$CWD/$i" status --porcelain)" ]]; then
            err "Path ${i} has uncommitted changes. Please fix."
        fi
    done
    grn "#### Verification complete - no uncommitted changes found ####"
    prin

    for files in success.list failed.list
    do
        rm $CWD/$files &> /dev/null
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

        if [[ "$PROJECTPATH" == "vendor/revengeos" ]]; then
            dbg "Detecting vendor/revengeos, checking out to $NEWBRANCH"
            git -C "$CWD/$PROJECTPATH" checkout -b "$NEWBRANCH" &> /dev/null
            echo "$PROJECTPATH" >> $CWD/success.list
            continue
        fi

        if wget -q --spider $repo_url; then
            blu "Merging $PROJECTPATH with $TAG"
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
            if git -C "$CWD/$PROJECTPATH" merge FETCH_HEAD &> /dev/null; then
                if [[ $(git -C "$CWD/$PROJECTPATH" rev-parse HEAD) != $(git -C "$CWD/$PROJECTPATH" rev-parse $REMOTE/$BRANCH) ]] && [[ $(git -C "$CWD/$PROJECTPATH" diff HEAD $REMOTE/$BRANCH) ]]; then
                    echo "$PROJECTPATH" >> $CWD/success.list
                    grn "Merging $PROJECTPATH success"
                else
                    prin "$PROJECTPATH - unchanged"
                    git -C "$CWD/$PROJECTPATH" checkout "${BRANCH}" &> /dev/null
                    git -C "$CWD/$PROJECTPATH" branch -D "$NEWBRANCH" &> /dev/null
                fi
            else
                echo "$PROJECTPATH" >> $CWD/failed.list
                red "$PROJECTPATH Merging failed"
            fi
        else
            red "Failed checking url $repo_url, please check connection"
            echo "$PROJECTPATH" >> $CWD/failed.list
        fi
        prin
    done

    prin
    grn "These repos success merging:"
    cat "$CWD/success.list"
    prin
    red "These repos failed merging:"
    cat "$CWD/failed.list"
    prin

    if [[ -f "$CWD/manifest/snippets/revengeos.xml" ]]
    then
        dbg "Detected RevengeOS XML. Trying to change branch with new merged branch"
        changeBranchManifest "$NEWBRANCH"
    fi 
}

doMergeAbort() {
    cat "$CWD/failed.list" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Repo $1 merged aborted"

        if ! git -C "$CWD/$1" merge --abort
        then
            red "Failed to merge abort"
            prin
            continue
        fi

        grn "Success"
        prin

    done
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

doBackup() {
    local BRANCH=$1
    local NEWBRANCH=$2

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        NOW=$(git -C $CWD/$1 branch --show-current)

        prin "Backup repo $1 to $NEWBRANCH"

        if ! git -C "$CWD/$1" checkout $BRANCH -b $NEWBRANCH &> /dev/null
        then
            red "Failed backup repo $1"
            prin
            continue
        fi

        git -C "$CWD/$1" checkout $NOW &> /dev/null

        grn "Success"
        prin

    done

    if [[ -f "$CWD/manifest/snippets/revengeos.xml" ]]
    then
        dbg "Detected RevengeOS XML. Trying to change branch with new backup branch"
        changeBranchManifest "$NEWBRANCH"
    fi
}

doRebaseAbort() {
    cat "$CWD/failed.list" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Repo $1 rebase aborted"

        if ! git -C "$CWD/$1" rebase --abort
        then
            red "Failed to rebase abort"
            prin
            continue
        fi

        grn "Success"
        prin

    done
}

doTag() {
    local TAG=$1

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Repo $1 add tag: $TAG"

        if ! git -C "$CWD/$1" tag $TAG &> /dev/null
        then
            red "Failed add tag for repo: $1"
            prin
            continue
        fi

        grn "Success"
        prin

    done
}

doTagDel() {
    local TAG=$1

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Repo $1 delete tag: $TAG"

        if ! git -C "$CWD/$1" tag -d $TAG
        then
            red "Failed delete tag for repo: $1"
            prin
            continue
        fi

        grn "Success"
        prin

    done
}

doBranchDel() {
    local BRANCH=$1

    cat "${LIST}" | while read l; do
        set ${l}

        if [ ! -d "$1" ]; then continue; fi

        prin "Repo $1 delete branch: $BRANCH"

        if ! git -C "$CWD/$1" branch -D $BRANCH
        then
            red "Failed delete branch for repo: $1"
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
    prin "  rebase-abort                        Abort all repo from from failed.list"
    prin "  merge <currentbranch> <aosptag>     Merge all repo with new aosp tag"
    prin "  merge-abort                         Abort all repo from from failed.list"
    prin "  push <remote> <branch>              Push all repo"
    prin "  push-force <remote> <branch>        Push all repo with flag --force"
    prin "  push-delete <remote> <branch>       Push all repo with flag --delete"
    prin "  backup <branch> <new branch>        Backup a branch with new branch"
    prin "  tag <new tag>                       Add new tag"
    prin "  tag-delete <tag>                    Delete existing tag"
    prin "  branch-delete <branch>              Delete existing branch in local"
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
        rebase-abort)
            checkPath
            doRebaseAbort
            exit
            ;;
        merge)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doMerge "$2" "$3"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: merge <currentbranch> <aospnewtag>"
            fi
            exit
            ;;
        merge-abort)
            checkPath
            doMergeAbort
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
        backup)
            if [ -n "$2" ] && [ -n "$3" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doBackup "$2" "$3"
                shift 2
            else
                err "Error: Argument for $1 is missing or more/less than 2 argument. Command: backup <branch> <new branch>"
            fi
            exit
            ;;
        tag)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doTag "$2"
                shift
            else
                err "Error: Argument for $1 is missing or more/less than 1 argument. Command: tag <new tag>"
            fi
            exit
            ;;
        tag-delete)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doTagDel "$2"
                shift
            else
                err "Error: Argument for $1 is missing or more/less than 1 argument. Command: tag-delete <tag>"
            fi
            exit
            ;;
        branch-delete)
            if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
                checkPath
                doBranchDel "$2"
                shift
            else
                err "Error: Argument for $1 is missing or more/less than 1 argument. Command: branch-delete <branch>"
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

usage
