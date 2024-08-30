#!/usr/bin/env bash
#
# backthatnasup(btnu)
#
# A script to deal with adhoc backups as well
# as scheduled backups when paired with
# a cron job. All parameters to be configured
# via a configuration file found in your '.config'
# directory.
#
# by CtrlAltMech
#

# Exit on error
set -e

# Configuration file to source from
readonly CONFIG="$HOME/.config/btnurc"

# Output Colors
readonly RED="\e[31m"
readonly GREEN="\e[32m"
readonly YELLOW="\e[33m"
readonly CYAN="\e[36m"
readonly ENDCOLOR="\e[0m"

# Option variables
selected_dir_group="" # Selected group of file paths go here
job_run_type="" # Tells us whether this is a mirror job or some other type (Only 2 types for now, mirror and not)
run_check="" # Is the job a dry-run or not

# Main Logic
main () {
    conf_check
    conf_var_check
#    conf_path_check     
#    check_server_alive

    while getopts ":mMrRhs:" OPTION;
    do
        case "$OPTION" in
            M) job_run_type="--delete";; # Run mirror job mirroring source directory
            R) :;; # Regular run with no-mirroring of source directory
            m) job_run_type="--delete"; run_check="--dry-run";; # Dry run of mirror job
            r) run_check="--dry-run";; # Dry run of run job
            s) selected_dir_group=$OPTARG;; # Allows you to select a specific group of directories from config file
            h) echo "Placeholder for help options";;
            \?) echo "Invalid selection placeholder";;
        esac
    done
    echo "$job_run_type"
    echo "$run_check"
    echo "$selected_dir_group"
    var_group_check "$selected_dir_group"
    conf_path_check "$selected_dir_group"
    rsync_job "$selected_dir_group" "$job_run_type" "$run_check"
}

# Check for configuration file
conf_check () {
    if  [[ -e $CONFIG ]]; then
        # shellcheck source=../../.config/btnurc
        . "$CONFIG"
    else
        conf_prompt
    fi
}

# Check to make sure the bare-minimum config variables are set.
conf_var_check () {
    local msg="$(echo -e "${RED}ONSITE variables and at least one directory need to be set in config.${ENDCOLOR}")"
    : "${DIRECTORIES:?$msg}"
    : "${ONSITE_BACKUP_HOST:?$msg}"
    : "${ONSITE_BACKUP_PATH:?$msg}"
    : "${ONSITE_USERNAME:?$msg}"
    : "${ONSITE_SSHKEY_PATH:?$msg}"
}

# Check to make sure the selected directories on the host are valid.
conf_path_check () {
    echo -e "${CYAN}Checking filepaths...${ENDCOLOR}\n"
    local dir_group="$1"
    [ -z "$dir_group" ] && dir_group="DIRECTORIES"
    eval "selected_group=(\"\${${dir_group}[@]}\")"
    for path in "${selected_group[@]}"
    do
        echo "$path"
    done
    echo -e "${GREEN}All filepaths are valid!${ENDCOLOR}\n"
}

var_group_check () {
    local dir_group="$1"
    [ -z "$dir_group" ] && dir_group="DIRECTORIES"
    if [[ -v "$dir_group" ]]; then
        :
    else
        echo "Directory group does not exist"
        exit 1
    fi

}

# If no configuration file is seen it will prompt to generate one 
conf_prompt () {
    local conf_choice
    read -p "$(echo -e "${YELLOW}No configuration file found. Would you like to create one? (y/n): ${ENDCOLOR}")" conf_choice
    
    while ! [[ $conf_choice =~ (^y$|^Y$|^n$|^N$) ]]
    do
        read -p "$(echo -e "${RED}Not a valid option. Would you like to create a config file? (y/n): ${ENDCOLOR}")" conf_choice
    done

    if [[ $conf_choice =~ (^y$|^Y$) ]]; then
        conf_make
    elif [[ "$conf_choice" =~ (^n$|^N$) ]]; then
        echo -e "${YELLOW}Goodbye!${ENDCOLOR}"
        exit 0
    fi
}

# Ping command to verify if server is online
host_ping () {
    for server in "$@"
    do
        if timeout 2 ping -c 1 "$server" &> /dev/null; then
            echo -e "${GREEN}$server looks to be up!${ENDCOLOR}"
        else
            echo -e "${RED}$server looks to be down :(${ENDCOLOR}"
            exit 1
        fi
    done
}

# Check to make sure your onsite/offsite/both server/s are up.
check_server_alive () {
    echo -e "${CYAN}Checking server status...${ENDCOLOR}\n"
    if [[ "$OFFSITE_BACKUP_HOST" != "" ]]; then
        host_ping "$ONSITE_BACKUP_HOST" "$OFFSITE_BACKUP_HOST"
        echo ""
    else
        host_ping "$ONSITE_BACKUP_HOST"
        echo ""
    fi
}

conf_make () {
	
	cat <<- EOF > "$CONFIG"
	# Config file for btnu
	
	# List of directories you want to backup.
	DIRECTORIES=(
		'/Example_directory/'
		'/Another/Example/'
		)
	
	# Meant to be a different host, but located locally
	# Enter IP or hostname.
	ONSITE_BACKUP_HOST=""
	
	# Path on the onsite host where the backup will be stored
	ONSITE_BACKUP_PATH=""
	
	# Username for onsite host
	ONSITE_USERNAME=""
	
	# Onsite host SSH priv key path
	ONSITE_SSHKEY_PATH=""
	
	# Meant to be a different host located offsite away from your onsite host.
	OFFSITE_BACKUP_HOST=""
	
	# Path on remote host where the backup will be stored
	OFFSITE_BACKUP_PATH=""
	
	# Username for offsite host
	OFFSITE_USERNAME=""
	
	# Offsite host SSH priv key path
	OFFSITE_SSHKEY_PATH=""
	
	EOF
    echo -e "${GREEN}Config file $CONFIG created!${ENDCOLOR}"
    $EDITOR $CONFIG # Open config in editor
    exit 0
}

# Handles the actual running of rsync job based on parameters passed to it. More functionality to come.
rsync_job () {
    local readonly rsync_ops="-avzhPpe"
    local dir_group="$1"
    local readonly dry_run_msg=$(echo -e "${YELLOW}Running DRY-RUN backup on $dir_group ${ENDCOLOR}")
    local readonly run_msg=$(echo -e "${CYAN}Running backup on $dir_group ${ENDCOLOR}")

    [ -z "$dir_group" ] && dir_group="DIRECTORIES"
    eval "selected_group=(\"\${${dir_group}[@]}\")"
    
    if [[ $3 == "--dry-run" ]]; then
        for dir in "${selected_group[@]}"
        do
            echo "$dir"
            echo "$dry_run_msg"
            rsync "$3" ${2:+"$2"} "$rsync_ops" "ssh -i $ONSITE_SSHKEY_PATH" "$dir" "$ONSITE_USERNAME"@"$ONSITE_BACKUP_HOST":"$ONSITE_BACKUP_PATH"
            echo ""
        done
    else
        for dir in "${selected_group[@]}"
        do
            echo "$dir"
            echo "$run_msg"
            rsync "$3" ${2:+"$2"} "$rsync_ops" "ssh -i $ONSITE_SSHKEY_PATH" "$dir" "$ONSITE_USERNAME"@"$ONSITE_BACKUP_HOST":"$ONSITE_BACKUP_PATH"
            echo ""
        done
    fi
    # dry run flag without mirroring passed if no arguments are passed to script
    # if [[ $1 == "-r" ]]; then
    #     for dir in "${DIRECTORIES[@]}"
    #     do
    #         echo -e "${YELLOW}Running DRY-RUN backup on $dir ${ENDCOLOR}"
    #         rsync --dry-run -avzhPpe "ssh -i $ONSITE_SSHKEY_PATH" "$dir" "$ONSITE_USERNAME"@"$ONSITE_BACKUP_HOST":"$ONSITE_BACKUP_PATH" 
    #         echo ""
    #     done
    # elif [[ $1 == "-R" ]]; then
    #     for dir in "${DIRECTORIES[@]}"
    #     do
    #         echo -e "${CYAN}Running backup on $dir ${ENDCOLOR}"
    #         rsync -avzhpPe "ssh -i $ONSITE_SSHKEY_PATH" "$dir" "$ONSITE_USERNAME"@"$ONSITE_BACKUP_HOST":"$ONSITE_BACKUP_PATH" 
    #         echo ""
    #     done
    # elif [[ $1 == "-m" ]]; then
    #     for dir in "${DIRECTORIES[@]}"
    #     do
    #         echo -e "${YELLOW}Running DRY-RUN backup on $dir ${ENDCOLOR}"
    #         rsync --dry-run --delete -avzhPpe "ssh -i $ONSITE_SSHKEY_PATH" "$dir" "$ONSITE_USERNAME"@"$ONSITE_BACKUP_HOST":"$ONSITE_BACKUP_PATH" 
    #         echo ""
    #     done
    # elif [[ $1 == "-M" ]]; then
    #     for dir in "${DIRECTORIES[@]}"
    #     do
    #         echo -e "${CYAN}Running backup on $dir ${ENDCOLOR}"
    #         rsync --delete -avzhPpe "ssh -i $ONSITE_SSHKEY_PATH" "$dir" "$ONSITE_USERNAME"@"$ONSITE_BACKUP_HOST":"$ONSITE_BACKUP_PATH" 
    #         echo ""
    #     done
    # else
    #     exit 1
    # fi
}

main "$@"











