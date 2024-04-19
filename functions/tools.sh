#!/bin/bash

# tools.sh is a shell wrapper intended to store commonly used functions.

# Function 'format_file' standardizes the format of the given file.
#   $1: file to be formatted
format_file() {
    file="$1"

    [[ ! -f "$file" ]] && return

    # Applicable to all files:
    # Remove carriage return characters, empty lines, and trailing whitespaces
    sed -i 's/\r//g; /^$/d; s/[[:space:]]*$//' "$file"

    # Applicable to specific files/extensions:
    case "$file" in
        'data/dead_domains.txt'|'data/parked_domains.txt')
            # Remove whitespaces, convert to lowercase, and remove duplicates
            mawk '{gsub(/ /, "", $0); print tolower($0)}' "$file" \
                | mawk '!seen[$0]++' > "${file}.tmp"
            ;;
        'config/parked_terms.txt')
            # Convert to lowercase, sort, and remove duplicates
            mawk '{print tolower($0)}' "$file" | sort -u -o "${file}.tmp"
            ;;
        *.txt|*.tmp)
            # Remove whitespaces, convert to lowercase, sort, and remove
            # duplicates
            mawk '{gsub(/ /, "", $0); print tolower($0)}' "$file" \
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
    for file in config/* data/*; do
        format_file "$file"
    done
}

# Function 'log_domains' logs domain processing events into the domain log.
#   $1: domains to log either in a file or variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
#   $4: timestamp (optional)
log_domains() {
    # Check if a file or variable was passed
    # Note [[ -s ]] causes unintended behavior when the file is empty
    if [[ -f "$1" ]]; then
        domains="$(<"$1")"
    else
        domains="$1"
    fi

    # Return if no domains were passed
    [[ -z "$domains" ]] && return

    timestamp="$4"
    timestamp="${timestamp:-$(date -u +"%H:%M:%S %d-%m-%y")}"

    printf "%s\n" "$domains" \
        | mawk -v event="$2" -v source="$3" -v time="$timestamp" \
        '{print time "," event "," $0 "," source}' >> config/domain_log.csv
}

# Function 'prune_lines' prunes lines in the given file to keep its number of
# lines within the given threshold.
#   $1: file to be pruned
#   $2: maximum number of lines to keep
prune_lines() {
    lines="$(wc -l < "$1")"

    if (( lines > $2 )); then
        # Do not delete the header in CSVs
        if [[ "$1" == *.csv ]]; then
            sed -i "2,$(( lines - $2 ))d" "$1"
            return
        fi

        sed -i "1,$(( lines - $2 ))d" "$1"
    fi
}

# Function 'download_toplist' downloads and formats the Tranco toplist.
# Output:
#   toplist.tmp
#   Telegram notification if an error occurred while downloading the toplist
download_toplist() {
    [[ -f toplist.tmp ]] && return

    wget -qO - 'https://tranco-list.eu/top-1m.csv.zip' | gunzip - \
        > toplist.tmp || send_telegram "Error downloading toplist."

    sed -i 's/^.*,//' toplist.tmp
    format_file toplist.tmp
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
    --send-telegram)
        send_telegram "$2"
        ;;
    *)
        printf "\n\e[1;31mInvalid argument: %s\e[0m\n\n" "$1"
        exit 1
        ;;
esac
