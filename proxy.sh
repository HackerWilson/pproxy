#!/bin/bash

# check if the shell is bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Please run it with bash. For example:"
    echo "bash ./proxy.sh"
    exit 1
fi

readonly TOOL_DEPS=(curl uname gzip chmod setsid grep kill)
readonly UNZIP_DEP_ALTERNATIVES=(unzip 7z bsdtar python3 jar)
UNZIP_DEP="UNSET"
readonly GITHUB_PROXIES=(
    "" # Direct connection
    https://github.akams.cn/
    https://github.moeyy.xyz/
    https://tvv.tw/
)
readonly GITHUB_SPEEDTEST_URL="https://raw.githubusercontent.com/microsoft/vscode/main/LICENSE.txt"

# Function to compare two floating-point numbers purely in Bash (Corrected Version)
# Usage: compare_floats NUM1 NUM2
# Output: Prints '<', '=', or '>' to standard output indicating if NUM1 is
#         less than, equal to, or greater than NUM2.
# Returns: 0 if comparison successful, 1 on error (e.g., invalid number)
compare_floats() {
    local num1_orig="$1"
    local num2_orig="$2"
    local result=""

    # --- Basic Input Validation (Optional but Recommended) ---
    local float_regex='^-?[0-9]*(\.[0-9]*)?$|^-?\.([0-9]+)$' # Allow empty integer part like .5
    if ! [[ "$num1_orig" =~ $float_regex ]]; then
        echo "Error: Invalid number format for first argument: '$num1_orig'" >&2
        return 1
    fi
     if ! [[ "$num2_orig" =~ $float_regex ]]; then
        echo "Error: Invalid number format for second argument: '$num2_orig'" >&2
        return 1
    fi

    # --- Handle Signs ---
    local sign1="" sign2=""
    [[ "$num1_orig" == "-"* ]] && sign1="-"
    [[ "$num2_orig" == "-"* ]] && sign2="-"

    if [[ "$sign1" == "-" && "$sign2" != "-" ]]; then
        result="<"
    elif [[ "$sign1" != "-" && "$sign2" == "-" ]]; then
        result=">"
    else
        # --- Signs are the same (or both zero/positive) ---
        local num1="${num1_orig#-}"
        local num2="${num2_orig#-}"

        # --- Separate Integer and Fractional Parts ---
        local int1="" frac1="" int2="" frac2=""

        if [[ "$num1" == *"."* ]]; then
            int1="${num1%%.*}"
            frac1="${num1#*.}"
        else
            int1="$num1"
            frac1=""
        fi
        # Handle cases like ".5" -> int="0", frac="5"
        # Handle empty int like "." -> int="0"
        [[ -z "$int1" ]] && int1="0"

        if [[ "$num2" == *"."* ]]; then
            int2="${num2%%.*}"
            frac2="${num2#*.}"
        else
            int2="$num2"
            frac2=""
        fi
        [[ -z "$int2" ]] && int2="0"

        # --- Pad Fractional Parts to Same Length ---
        local len1="${#frac1}"
        local len2="${#frac2}"
        local max_decimals=$(( len1 > len2 ? len1 : len2 ))

        while [[ "${#frac1}" -lt "$max_decimals" ]]; do frac1="${frac1}0"; done
        while [[ "${#frac2}" -lt "$max_decimals" ]]; do frac2="${frac2}0"; done

        # --- Combine Parts into Integer Strings (No Integer Padding Needed Here) ---
        # We will compare these numerically after removing leading zeros.
        local comp1="${int1}${frac1}"
        local comp2="${int2}${frac2}"

        # --- **CRITICAL FIX AREA** ---
        # Remove leading zeros BEFORE integer comparison to avoid octal issues and ensure correct base-10 comparison
        comp1="${comp1#"${comp1%%[!0]*}"}" # Remove leading zeros
        comp2="${comp2#"${comp2%%[!0]*}"}" # Remove leading zeros
        # Handle the case where the number was zero or became empty after removing zeros (e.g., "0.0")
        comp1="${comp1:-0}"
        comp2="${comp2:-0}"

        # --- Compare the resulting numbers using Bash INTEGER comparison ---
        local cmp_result=""
        # Note: Using [[ ]] with arithmetic operators is safer than (( )) or [ ]
        if [[ "$comp1" -lt "$comp2" ]]; then cmp_result="<";
        elif [[ "$comp1" -gt "$comp2" ]]; then cmp_result=">";
        else cmp_result="="; fi
        # --- End Critical Fix Area ---

        # --- Adjust result if both numbers were negative ---
        if [[ "$sign1" == "-" ]]; then # (implies sign2 is also "-")
            if [[ "$cmp_result" == "<" ]]; then result=">";
            elif [[ "$cmp_result" == ">" ]]; then result="<";
            else result="="; fi
        else
            result="$cmp_result"
        fi
    fi

    echo "$result"
    return 0
}

COLOR_GREEN=""
COLOR_RED=""
COLOR_YELLOW=""
COLOR_NORMAL=""
COLOR_UNDERLINE=""
setup_color_support() {
    # check if the stdout is a terminal
    if [ ! -t 1 ]; then
        return 1
    fi
    # check if the terminal supports color
    if ! command -v tput >/dev/null 2>&1; then
        return 1
    fi
    local ncolors
    ncolors=$(tput colors)
    if [ "$ncolors" -lt 8 ]; then
        return 1
    fi
    # get color codes
    COLOR_GREEN=$(tput setaf 2)
    COLOR_RED=$(tput setaf 1)
    COLOR_YELLOW=$(tput setaf 3)
    COLOR_NORMAL=$(tput sgr0)
    COLOR_UNDERLINE=$(tput smul)
    return 0
}

# Log with indent
# Usage: log "level" "message"
LOG_INDENT=0
log() {
    local level="$1"
    local message="$2"
    case "$level" in
        "DEBUG")
            level="${COLOR_GREEN}DEBUG${COLOR_NORMAL}"
            ;;
        "INFO")
            level="${COLOR_GREEN}INFO${COLOR_NORMAL}"
            ;;
        "WARN")
            level="${COLOR_YELLOW}WARN${COLOR_NORMAL}"
            ;;
        "ERROR")
            level="${COLOR_RED}ERROR${COLOR_NORMAL}"
            ;;
        *)
            level="${COLOR_NORMAL}$level${COLOR_NORMAL}"
            ;;
    esac
    if [ $LOG_INDENT -eq 0 ]; then
        printf "[%s] %s\n" "$level" "$message" >&2
    else
        local minus_count=$((LOG_INDENT - 3)) # how many "-"s in " -> "
        printf "[%s] " "$level" >&2
        for ((i=0; i<minus_count; i++)); do
            printf "-" >&2
        done
        printf "> %s\n" "$message" >&2
    fi
}
log_sublevel_start() {
    LOG_INDENT=$((LOG_INDENT + 4))
}
log_sublevel_end() {
    LOG_INDENT=$((LOG_INDENT - 4))
}

# Check dependencies. 
# Usage: check_dep [<dependency command>]
# Returns: 0 if <dependency command> is provided and exists, 1 if it doesn't exist. 
# If <dependency command> is not provided, checks all dependencies in TOOL_DEPS and UNZIP_DEP_ALTERNATIVES. Exit directly if any of them is not found.
check_dep() {
    if [ "$#" -gt 0 ]; then
        # Check specific dependency
        local dep="$1"
        if ! command -v "$dep" >/dev/null 2>&1; then
            return 1
        fi
        return 0
    fi
    for dep in "${TOOL_DEPS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log "ERROR" "Tool $dep is not installed. Please install it and try again."
            exit 1
        fi
    done
    for dep in "${UNZIP_DEP_ALTERNATIVES[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            UNZIP_DEP="$dep"
            break
        fi
    done
    if [ "$UNZIP_DEP" == "UNSET" ]; then
        log "ERROR" "No unzip tool found. Please install one of the following: ${UNZIP_DEP_ALTERNATIVES[*]}."
        exit 1
    fi
}

smart_unzip() {
    local file="$1"
    local dest="$2"
    case "$UNZIP_DEP" in
        unzip)
            command unzip -o "$file" -d "$dest"
            ;;
        7z)
            command 7z x -y "$file" -o"$dest"
            ;;
        bsdtar)
            command bsdtar --extract --file "$file" --directory "$dest"
            ;;
        python3)
            command python3 -m zipfile --extract "$file" "$dest"
            ;;
        jar)
            command jar --extract --file="$file" -C "$dest"
            ;;
        UNSET)
            log "ERROR" "No unzip tool found. Please install one of the following: ${UNZIP_DEP_ALTERNATIVES[*]}."
            exit 1
            ;;
    esac
}

FASTEST_GITHUB_PROXY="UNSET"
github_proxy_select() {
    if [ "$FASTEST_GITHUB_PROXY" != "UNSET" ]; then
        # Already selected
        return
    fi

    log "INFO" "Selecting fastest GitHub proxy..."
    log_sublevel_start
    local min_time=10.0
    for proxy in "${GITHUB_PROXIES[@]}"; do
        local curl_time
        if ! curl_time=$(curl --silent --fail --location --output /dev/null --max-time 3 --write-out "%{time_total}" "$proxy$GITHUB_SPEEDTEST_URL"); then
            # if return error, skip
            log "WARN" "Proxy '$proxy' is not available"
            continue
        fi

        if [ -z "$proxy" ]; then
            log "INFO" "Direct connection time: $curl_time s"
        else
            log "INFO" "Proxy '$proxy' time: $curl_time s"
        fi

        if [ "$(compare_floats "$curl_time" "$min_time")" == "<" ]; then
            min_time="$curl_time"
            FASTEST_GITHUB_PROXY="$proxy"
            # log "DEBUG" "Current fastest proxy: $FASTEST_GITHUB_PROXY ($min_time s)"
        fi
    done
    if [ "$FASTEST_GITHUB_PROXY" == "UNSET" ]; then
        log "ERROR" "No GitHub proxy available"
        exit 1
    fi
    log_sublevel_end
    if [ -z "$FASTEST_GITHUB_PROXY" ]; then
        log "INFO" "Fastest GitHub proxy: Direct connection"
        return
    else
        log "INFO" "Fastest GitHub proxy: $FASTEST_GITHUB_PROXY"
    fi
}

# Obtain Mihomo-specific OS name to build the download URL
obtain_mihomo_os() {
    local uname_os
    uname_os=$(uname --kernel-name)
    local mihomo_os
    case "$uname_os" in
        Darwin)
            mihomo_os="darwin"
            ;;
        Linux)
            mihomo_os="linux"
            ;;
        *)
            log "ERROR" "Unsupported OS: $uname_os"
            exit 1
            ;;
    esac
    echo "$mihomo_os"
}

# Obtain Mihomo-specific architecture name to build the download URL
obtain_mihomo_arch() {
    local uname_arch
    uname_arch=$(uname --machine)
    local mihomo_arch
    case "$uname_arch" in
        x86_64)
            mihomo_arch="amd64"
            ;;
        aarch64)
            mihomo_arch="arm64"
            ;;
        armv7l)
            mihomo_arch="armv7"
            ;;
        riscv64)
            mihomo_arch="riscv64"
            ;;
        i686)
            mihomo_arch="386"
            ;;
        *)
            log "ERROR" "Unsupported architecture: $uname_arch"
            exit 1
            ;;
    esac
    echo "$mihomo_arch"
}

download_mihomo() {
    log "INFO" "Downloading Mihomo..."
    
    log_sublevel_start

    # 1. Fetch the latest version
    log "INFO" "Fetching the latest release info..."
    log_sublevel_start
    readonly MIHOMO_LATEST_VERSION_URL="https://github.com/MetaCubeX/mihomo/releases/latest/download/version.txt"
    local mihomo_latest_version
    if ! mihomo_latest_version=$(curl --silent --fail --location "$FASTEST_GITHUB_PROXY$MIHOMO_LATEST_VERSION_URL"); then
        log "ERROR" "Failed to fetch the latest release info"
        exit 1
    fi
    if [ -z "$mihomo_latest_version" ]; then
        log "ERROR" "The latest release info is empty"
        exit 1
    fi
    log "INFO" "Latest version: $mihomo_latest_version"
    log_sublevel_end

    # 2. Download
    log "INFO" "Downloading..."
    log_sublevel_start
    # shellcheck disable=SC2155
    readonly MIHOMO_DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/$mihomo_latest_version/mihomo-$(obtain_mihomo_os)-$(obtain_mihomo_arch)-$mihomo_latest_version.gz"
    log "INFO" "Download from: ${COLOR_UNDERLINE}$MIHOMO_DOWNLOAD_URL${COLOR_NORMAL}"
    if ! curl --fail --location "$FASTEST_GITHUB_PROXY$MIHOMO_DOWNLOAD_URL" --output "proxy-data/mihomo.gz"; then
        log "ERROR" "Failed to download Mihomo"
        exit 1
    fi
    log "INFO" "Downloaded to proxy-data/mihomo.gz"
    log_sublevel_end

    # 3. Unzip
    log "INFO" "Unzipping..."
    log_sublevel_start
    if ! gzip --decompress --force "proxy-data/mihomo.gz"; then
        log "ERROR" "Failed to unzip Mihomo"
        exit 1
    fi
    if ! chmod +x "proxy-data/mihomo"; then
        log "ERROR" "Failed to make mihomo executable"
        exit 1
    fi
    log "INFO" "Unzipped to proxy-data/mihomo"
    log_sublevel_end

    log_sublevel_end
}

mihomo_exist() {
    if [ -s "proxy-data/mihomo" ]; then
        # Check if mihomo is executable
        if [ ! -x "proxy-data/mihomo" ]; then
            if ! chmod +x "proxy-data/mihomo"; then
                log "ERROR" "Mihomo exists but not executable and we failed to make it executable"
                exit 1
            fi
        fi
        if ./proxy-data/mihomo -v; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

download_metacubexd() {
    readonly METACUBEXD_DOWNLOAD_URL="https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"
    log "INFO" "Downloading metacubexd..."
    log_sublevel_start

    # 1. Download
    log "INFO" "Downloading..."
    log_sublevel_start
    log "INFO" "Download from: ${COLOR_UNDERLINE}$METACUBEXD_DOWNLOAD_URL${COLOR_NORMAL}"
    if ! curl --fail --location "$FASTEST_GITHUB_PROXY$METACUBEXD_DOWNLOAD_URL" --output "proxy-data/metacubexd.zip"; then
        log "ERROR" "Failed to download metacubexd"
        exit 1
    fi
    log "INFO" "Downloaded to proxy-data/metacubexd.zip"
    log_sublevel_end

    # 2. Unzip
    log "INFO" "Unzipping..."
    log_sublevel_start
    rm --recursive --force "proxy-data/metacubexd/"
    if ! smart_unzip "proxy-data/metacubexd.zip" "proxy-data/metacubexd/"; then
        log "ERROR" "Failed to unzip metacubexd"
        exit 1
    fi
    if [ ! -d "proxy-data/metacubexd/" ]; then
        log "ERROR" "Failed to unzip metacubexd"
        exit 1
    fi
    log "INFO" "Unzipped to proxy-data/metacubexd"
    # strip the first directory layer
    shopt -s nullglob dotglob
    local unarchived_file_list=("proxy-data/metacubexd/"*)
    if (( ${#unarchived_file_list[@]} == 1 )) && [ -d "${unarchived_file_list[0]}" ]; then
        log "INFO" "Stripping the first directory layer..."
        mv "${unarchived_file_list[0]}"/* "proxy-data/metacubexd/"
        rmdir "${unarchived_file_list[0]}"
    fi
    rm "proxy-data/metacubexd.zip"
    log_sublevel_end

    log_sublevel_end
}

download_geodata_if_necessary() {
    if [ ! -f "proxy-data/config/geosite.dat" ]; then
        github_proxy_select
        log "INFO" "Downloading geosite..."
        log_sublevel_start
        readonly MIHOMO_GEOSITE_DOWNLOAD_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
        log "INFO" "Download from: ${COLOR_UNDERLINE}$MIHOMO_GEOSITE_DOWNLOAD_URL${COLOR_NORMAL}"
        if ! curl --fail --location "$FASTEST_GITHUB_PROXY$MIHOMO_GEOSITE_DOWNLOAD_URL" --output "proxy-data/config/geosite.dat"; then
            log "WARN" "Failed to download geosite"
        else
            log "INFO" "Downloaded to proxy-data/config/geosite.dat"
        fi
        log_sublevel_end
    fi

    if [ ! -f "proxy-data/config/geoip.dat" ]; then
        github_proxy_select
        log "INFO" "Downloading geoip..."
        log_sublevel_start
        readonly MIHOMO_GEOIP_DOWNLOAD_URL="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
        log "INFO" "Download from: ${COLOR_UNDERLINE}$MIHOMO_GEOIP_DOWNLOAD_URL${COLOR_NORMAL}"
        if ! curl --fail --location "$FASTEST_GITHUB_PROXY$MIHOMO_GEOIP_DOWNLOAD_URL" --output "proxy-data/config/geoip.dat"; then
            log "WARN" "Failed to download geoip"
        else
            log "INFO" "Downloaded to proxy-data/config/geoip.dat"
        fi
        log_sublevel_end
    fi
}

daemon_run() {
    local tag=$1
    shift
    local output_file=$1
    shift
    # https://stackoverflow.com/questions/3430330/best-way-to-make-a-shell-script-daemon
    ( umask 0; _TAG="$tag" setsid "$@" </dev/null &>"$output_file" & ) &
}

kill_by_tag() {
    local tag=$1
    local grepped_files
    grepped_files=$(grep --files-with-matches "\b_TAG=$tag\b" /proc/[0-9]*/environ 2>/dev/null)
    local tagged_pids=()
    while read -r grepped_file; do
        if [[ "$grepped_file" =~ /proc/([0-9]+)/environ ]]; then
            tagged_pids+=("${BASH_REMATCH[1]}")
    fi
    done <<< "$grepped_files"

    if [ "${#tagged_pids[@]}" -gt 0 ]; then
        log "INFO" "Killing pids: ${tagged_pids[*]}"
        kill -SIGTERM "${tagged_pids[@]}"
        return 0
    fi
    return 2
}

find_unused_port() {
    local LOW_BOUND=9090
    local RANGE=16384
    for ((i=0; i<RANGE; i++)); do
        local CANDIDATE=$((LOW_BOUND + i))
        if ! (echo -n >/dev/tcp/127.0.0.1/${CANDIDATE}) >/dev/null 2>&1; then
            echo $CANDIDATE
            return 0
        fi
    done
    log "ERROR" "No available port found in the range $LOW_BOUND-$((LOW_BOUND + RANGE - 1))"
    return 1
}

if setup_color_support; then
    log "DEBUG" "Terminal supports color"
else
    log "DEBUG" "Terminal does not support color"
fi
check_dep

if [ "$1" == "stop" ]; then
    kill_by_tag mihomo
    exit 0
fi

mkdir --parents "proxy-data/" 

if mihomo_version_output=$(mihomo_exist); then
    log "INFO" "Mihomo already exists, skip downloading. Version: "
    echo "$mihomo_version_output"
else
    github_proxy_select
    download_mihomo
fi

if [ -d "proxy-data/metacubexd/" ]; then
    log "INFO" "metacubexd already exists, skip downloading."
else
    github_proxy_select
    download_metacubexd
fi

mkdir --parents "proxy-data/config" 
download_geodata_if_necessary

kill_by_tag mihomo
if ext_port=$(find_unused_port); then
    log "INFO" "Found unused port: $ext_port"
else
    log "ERROR" "Failed to find an unused port"
    exit 1
fi
daemon_run mihomo ./proxy-data/mihomo.log ./proxy-data/mihomo -d "proxy-data/config" -ext-ctl "0.0.0.0:$ext_port" -ext-ui "$(realpath proxy-data/metacubexd)"

log "INFO" "Mihomo started in the background. You can access the web UI at ${COLOR_UNDERLINE}http://<server-ip>:$ext_port/ui$COLOR_NORMAL"
log "INFO" "You may need to put your subscription file at proxy-data/config/config.yaml and restart Mihomo."
me=${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}
log "INFO" "To stop Mihomo, run: $me stop"


# ==== Tunneling the WebUI through a free service ====
tunnel_ask_next_or_exit() {
    local service_name=$1
    shift
    local exit_code=$1
    log "WARN" "Tunneling through $service_name exited with code $exit_code. Because we cannot have any assumptions about the exit code, we don't know if it was successful."
    read -p "[QUESTION] Do you want to try next service? Press n if you want to exit. (y/n)" -n 1 -r next_service_choice
    echo
    if [[ $next_service_choice == [yY] ]]; then
        return 0
    fi
    return 1
}

try_tunnel_service() {
    local tunnel_port=$1

    log "INFO" "Tunneling the WebUI through a free service..."
    log_sublevel_start
    # check ssh
    if ! check_dep ssh; then
        log "ERROR" "SSH is not installed. Please install it and try again."
        log_sublevel_end
        return 1
    fi

    log "INFO" "Note: after you start the tunnel, you can usually access the WebUI at ${COLOR_UNDERLINE}https://<the-service-random-subdomain>/ui${COLOR_NORMAL}."
    log "INFO" "    You can then use ${COLOR_UNDERLINE}https://<the-service-random-subdomain>/${COLOR_NORMAL} as the control server address in the WebUI."
    readonly SSH_DEFAULT_PARAMS=(
        -o StrictHostKeyChecking=no # skip host key checking
        -o ServerAliveInterval=30 # send keep-alive packets
        -o ConnectTimeout=5 # set connection timeout
    )
    # - tunnel through pinggy.io
    log "INFO" "Try tunneling through pinggy.io..."
    ssh -p 443 "${SSH_DEFAULT_PARAMS[@]}" -t -R0:localhost:"$tunnel_port" a.pinggy.io x:passpreflight
    if ! tunnel_ask_next_or_exit "pinggy.io" $?; then
        log_sublevel_end
        return
    fi

    # - tunnel through localhost.run
    log "INFO" "Try tunneling through localhost.run..."
    ssh "${SSH_DEFAULT_PARAMS[@]}" -R80:localhost:"$tunnel_port" localhost.run
    if ! tunnel_ask_next_or_exit "localhost.run" $?; then
        log_sublevel_end
        return
    fi

    # - tunnel through serveo.net
    log "INFO" "Try tunneling through serveo.net..."
    ssh "${SSH_DEFAULT_PARAMS[@]}" -R80:localhost:"$tunnel_port" serveo.net
    if ! tunnel_ask_next_or_exit "serveo.net" $?; then
        log_sublevel_end
        return
    fi

    log "ERROR" "All tunneling services failed. Please try again later."
    log_sublevel_end
    return 1
}

# ask user whether to tunnel the WebUI through free service
read -p "[QUESTION] Do you want to tunnel the WebUI through a free service, so that you can access it remotely? (y/n) " -n 1 -r tunnel_choice
echo
if [[ $tunnel_choice == [yY] ]]; then
    try_tunnel_service "$ext_port"
else
    log "INFO" "Skipping tunneling."
fi