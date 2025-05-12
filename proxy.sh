#!/bin/bash

readonly TOOL_DEPS=(curl uname gzip unzip chmod setsid grep cut kill)
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

# Log with indent
# Usage: log "level" "message"
LOG_INDENT=0
log() {
    local level="$1"
    local message="$2"
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

check_dep() {
    for dep in "${TOOL_DEPS[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log "ERROR" "Tool $dep is not installed. Please install it and try again."
            exit 1
        fi
    done
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
        if ! curl_time=$(curl --silent --fail --output /dev/null --max-time 3 --write-out "%{time_total}" "$proxy$GITHUB_SPEEDTEST_URL"); then
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
    log "INFO" "Download from: $MIHOMO_DOWNLOAD_URL"
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
    log "INFO" "Download from: $METACUBEXD_DOWNLOAD_URL"
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
    if ! unzip -o "proxy-data/metacubexd.zip" -d "proxy-data/metacubexd/"; then
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
        log "INFO" "Download from: $MIHOMO_GEOSITE_DOWNLOAD_URL"
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
        log "INFO" "Download from: $MIHOMO_GEOIP_DOWNLOAD_URL"
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
    local tagged_pids
    if ! tagged_pids=$(grep --files-with-matches "\b_TAG=$tag\b" /proc/[0-9]*/environ 2>/dev/null | cut --delimiter=/ --fields=3); then
        return 1
    fi
    if [ -n "$tagged_pids" ]; then
        log "INFO" "Killing pids: $tagged_pids"
        kill -SIGTERM "$tagged_pids"
        return 0
    fi
    return 2
}

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
daemon_run mihomo ./proxy-data/mihomo.log ./proxy-data/mihomo -d "proxy-data/config" -ext-ctl "0.0.0.0:9091" -ext-ui "$(realpath proxy-data/metacubexd)"

log "INFO" "Mihomo started in the background. You can access the web UI at http://<server-ip>:9091/ui"
log "INFO" "You may need to put your subscription file at proxy-data/config/config.yaml and restart Mihomo."
me=${BASH_SOURCE[${#BASH_SOURCE[@]} - 1]}
log "INFO" "To stop Mihomo, run: $me stop"