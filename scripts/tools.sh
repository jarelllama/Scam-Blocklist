#!/bin/bash

# tools.sh is a shell wrapper that stores commonly used functions.

# Function 'format_file' standardizes the format of the given file.
# Input:
#   $1: file to be formatted
format_file() {
    local file="$1"

    [[ ! -f "$file" ]] && return

    # Applicable to all files:
    # Remove carriage return characters, empty lines, and trailing whitespaces
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' "$file"

    # Applicable to specific files/extensions:
    case "$file" in
        'data/dead_domains.txt'|'data/parked_domains.txt')
            # Remove duplicates, whitespaces, and convert to lowercase
            mawk '!seen[$0]++ {gsub(/ /, ""); print tolower($0)}' "$file" \
                > "${file}.tmp"
            ;;
        'config/parked_terms.txt')
            # Convert to lowercase, sort, and remove duplicates
            mawk '{print tolower($0)}' "$file" | sort -u -o "${file}.tmp"
            ;;
        *.txt|*.tmp)
            # Remove whitespaces, convert to lowercase, sort, and remove
            # duplicates
            mawk '{gsub(/ /, ""); print tolower($0)}' "$file" \
                | sort -u -o "${file}.tmp"
            ;;
        *)
            return
            ;;
    esac

    [[ -f "${file}.tmp" ]] && mv "${file}.tmp" "$file"
}

# Function 'format_all' formats all files in the config and data directories.
format_all() {
    local file
    for file in config/* data/*; do
        format_file "$file"
    done
}

# Function 'convert_unicode' converts Unicode to Punycode.
# Input:
#   $1: file to process
convert_unicode() {
    # Install idn2 (requires sudo. -qq doesn not work here)
    command -v idn2 > /dev/null || sudo apt-get install idn2 > /dev/null

    # Process the file, handling entries that may cause idn2 to error:
    # https://www.rfc-editor.org/rfc/rfc5891#section-4.2.3.1. If idn2 does
    # error, exit 1.
    {
        grep -vE '\-\.|..--' "$1" | idn2 || exit 1
        grep -E '\-\.|..--' "$1"
    } | sort -u -o "$1"
}

# Function 'log_domains' logs domain processing events into the domain log.
# Input:
#   $1: domains to log either in a file or variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_domains() {
    local domains timestamp

    # Check if a file or variable was passed
    # Note [[ -s ]] causes unintended behavior when the file is empty
    if [[ -f "$1" ]]; then
        domains="$(<"$1")"
    else
        domains="$1"
    fi

    # Return if no domains were passed
    [[ -z "$domains" ]] && return

    timestamp="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")"

    printf "%s\n" "$domains" \
        | mawk -v event="$2" -v source="$3" -v time="$timestamp" \
        '{print time "," event "," $0 "," source}' >> config/domain_log.csv
}

# Function 'prune_lines' prunes lines in the given file to keep its number of
# lines within the given threshold.
# Input:
#   $1: file to be pruned
#   $2: maximum number of lines to keep
prune_lines() {
    local file="$1"
    local max_lines="$2"
    local lines
    lines="$(wc -l < "$1")"

    if (( lines > max_lines )); then
        # Do not delete the header in CSVs
        if [[ "$file" == *.csv ]]; then
            sed -i "2,$(( lines - max_lines ))d" "$file"
            return
        fi

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

    # curl -L required
    curl -sSL 'https://tranco-list.eu/top-1m.csv.zip' | gunzip - \
        > toplist.tmp || send_telegram "Error downloading toplist."

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

    local url1='https://raw.githubusercontent.com/xRuffKez/NRD/refs/heads/main/lists/30-day/domains-only/nrd-30day_part1.txt'
    local url2='https://raw.githubusercontent.com/xRuffKez/NRD/refs/heads/main/lists/30-day/domains-only/nrd-30day_part2.txt'
    local url3='https://raw.githubusercontent.com/SystemJargon/filters/refs/heads/main/nrds-30days.txt'
    local url4='https://feeds.opensquat.com/domain-names-month.txt'

    # Download the feeds in parallel and get only domains, ignoring comments
    curl -sSLZH 'User-Agent: openSquat-2.1.0' "$url1" "$url2" "$url3" "$url4" \
        | grep -oE '^[[:alnum:]][[:alnum:].-]*[[:alnum:]]\.[[:alnum:]-]*[a-z]{2,}[[:alnum:]-]*$' \
        > nrd.tmp

    format_file nrd.tmp
}

# Function 'send_telegram' sends a Telegram notification with the given
# message.
# Input:
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

set -e

case "$1" in
    --format)
        format_file "$2"
        ;;
    --format-all)
        format_all
        ;;
    --convert-unicode)
        convert_unicode "$2"
        ;;
    --log-domains)
        log_domains "$2" "$3" "$4"
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
        printf "\n\e[1;31mInvalid argument: %s\e[0m\n\n" "$*" >&2
        exit 1
        ;;
esac
