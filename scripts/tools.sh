#!/bin/bash

# tools.sh is a shell wrapper intended to store commonly used functions.

# Function 'format_file' standardizes the format of the given file.
#   $1: file to be formatted
format_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return
    fi
    
    # Applicable to all files:
    # Remove carriage return characters, empty lines, and trailing whitespaces
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' "$file"

    # Applicable to specific files/extensions:
    case "$file" in
        data/dead_domains.txt|data/parked_domains.txt)
            # Remove duplicates, whitespaces, and convert to lowercase
            awk '!seen[$0]++ {gsub(/ /, "", $0); print tolower($0)}' "$file" > "${file}.tmp"
            ;;
        config/parked_terms.txt)
            # Convert to lowercase, sort, and remove duplicates
            awk '{print tolower($0)}' "$file" | sort -u -o "${file}.tmp"
            ;;
        *.txt|*.tmp)
            # Remove whitespaces, convert to lowercase, sort, and remove duplicates
            awk '{gsub(/ /, "", $0); print tolower($0)}' "$file" | sort -u -o "${file}.tmp"
            ;;
        *)
            return
            ;;
    esac

    [[ -f "${file}.tmp" ]] && mv "${file}.tmp" "$file"
}

# Function 'format_all' formats all files in the config and data directories.
format_all() {
    find config data -type f -exec format_file {} \;
}

# Function 'log_domains' logs domain processing events into the domain log.
#   $1: domains to log either in a file or variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
#   $4: timestamp (optional)
log_domains() {
    local domains="$1"
    local event="$2"
    local source="$3"
    local timestamp="${4:-$(date -u +"%H:%M:%S %d-%m-%y")}"

    if [[ -z "$domains" ]]; then
        return
    fi

    printf "%s\n" "$domains" | awk -v event="$event" -v source="$source" -v time="$timestamp" \
        '{print time "," event "," $0 "," source}' >> config/domain_log.csv
}

# Function 'prune_lines' prunes lines in the given file to keep its number of
# lines within the given threshold.
#   $1: file to be pruned
#   $2: maximum number of lines to keep
prune_lines() {
    local file="$1"
    local max_lines="$2"
    local lines=$(wc -l < "$file")

    if (( lines > max_lines )); then
        # Do not delete the header in CSVs
        sed -i "1,$(( lines - max_lines ))d" "$file"
    fi
}

# Function 'download_toplist' downloads and formats the Tranco toplist. Note
# that the toplist does not contain subdomains.
# Output:
#   toplist.tmp
#   Telegram notification if an error occurred while downloading the toplist
download_toplist() {
    [[ -f toplist.tmp ]] && return

    curl -sSL 'https://tranco-list.eu/top-1m.csv.zip' | gunzip - > toplist.tmp || send_telegram "Error downloading toplist."

    sed -i 's/^.*,//' toplist.tmp
    format_file toplist.tmp
}

# Function 'download_nrd_feed' downloads and collates NRD feeds consisting
# domains registered in the last 30 days.
# Output:
#   nrd.tmp
#   Telegram notification if an error occurred while downloading the NRD feeds
download_nrd_feed() {
    [[ -f nrd.tmp ]] && return

    url1='https://raw.githubusercontent.com/shreshta-labs/newly-registered-domains/main/nrd-1m.csv' # This feed is not complete. I think shreshta has a trial or sample source?
    url2='https://feeds.opensquat.com/domain-names-month.txt' # I RECEIVED ERROR 403! IS THIS FEED TEMPORARELY DOWN?
    url3='https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/nrds.30-onlydomains.txt'

    {
        curl -sSL "$url1" || send_telegram "Error occurred while downloading NRD feeds."

        # Download the bigger feeds in parallel
        curl -sSLZH 'User-Agent: openSquat-2.1.0' "$url2" "$url3"
    } | awk '!/#/' > nrd.tmp

    # Appears to be the best way of checking if the bigger feeds downloaded
    # properly without checking each feed individually and losing
    # parallelization.
    if (( $(wc -l < nrd.tmp) < 9000000 )); then
        send_telegram "Error occurred while downloading NRD feeds."
    fi

    format_file nrd.tmp
}

# Function 'send_telegram' sends a Telegram notification with the given
# message.
#   $TELEGRAM_CHAT_ID:   Telegram user Chat ID
#   $TELEGRAM_BOT_TOKEN: Telegram Bot Token
#   $1: message body
send_telegram() {
    curl -sSX POST \
        -H 'Content-Type: application/json' \
        -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": \"$1\"}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -o /dev/null
}

# Entry point
case "$1" in
    --format)
        format_file "$2"
        ;;
    --format-all)
        format_all
        ;;
    --log-domains)
        log_domains "$2" "$3" "$4" "$5"
        ;;
    --prune-lines)
        prune_lines "$2" "$3"
        ;;
    --download-toplist)
        download_toplist
        ;;
    --download-nrd-feed)
        download_nrd_feed
        ;;
    --send-telegram)
        send_telegram "$2"
        ;;
    *)
        printf "\n\e[1;31mInvalid argument: %s\e[0m\n\n" "$1"
        exit 1
        ;;
esac

exit 0
