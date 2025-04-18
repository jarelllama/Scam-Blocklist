#!/bin/bash

# tools.sh is a shell wrapper that stores commonly used functions.

readonly DEAD_DOMAINS='data/dead_domains.txt'
readonly PARKED_DOMAINS='data/parked_domains.txt'
readonly BLACKLIST='config/blacklist.txt'
readonly DOMAIN_LOG='config/domain_log.csv'
readonly PARKED_TERMS='config/parked_terms.txt'
readonly REVIEW_CONFIG='config/review_config.csv'
readonly SUBDOMAINS='config/subdomains.txt'
readonly WHITELIST='config/whitelist.txt'
readonly DOMAIN_REGEX='(?:([\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]|[\p{L}\p{N}])\.)+[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]'

# Convert Unicode to Punycode.
# Input:
#   $1: file to process
convert_unicode() {
    # Install idn2 (requires sudo. -qq does not work here)
    command -v idn2 > /dev/null || sudo apt-get install idn2 > /dev/null

    # Process the file, handling entries that may cause idn2 to error:
    # https://www.rfc-editor.org/rfc/rfc5891#section-4.2.3.1. If idn2 does
    # error, exit 1.
    mawk '/^..--/' "$1" > temp
    mawk '!/^..--/' "$1" | idn2 >> temp || error 'idn2 errored.'
    mv temp "$1"
    sort -u "$1" -o "$1"
}

# Download and collate NRD feeds consisting domains registered in the last 30
# days.
# Output:
#   nrds.tmp
download_nrd_feed() {
    [[ -s nrds.tmp ]] && return

    local -a urls=(
        https://raw.githubusercontent.com/xRuffKez/NRD/refs/heads/main/lists/30-day/domains-only/nrd-30day_part1.txt
        https://raw.githubusercontent.com/xRuffKez/NRD/refs/heads/main/lists/30-day/domains-only/nrd-30day_part2.txt
        https://raw.githubusercontent.com/SystemJargon/filters/refs/heads/main/nrds-30days.txt
        https://feeds.opensquat.com/domain-names-month.txt
    )

    # Download the feeds in parallel and get domains
    curl -sSLZH 'User-Agent: openSquat-2.1.0' "${urls[@]}" \
        | grep -P "^${DOMAIN_REGEX}$" > nrds.tmp
    # TODO: error detection

    format_file nrds.tmp
}

# Download and format the Tranco toplist.
# Output:
#   toplist.tmp
download_toplist() {
    [[ -s toplist.tmp ]] && return

    local url='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/tranco.txt'

    curl -sSL --retry 2 --retry-all-errors "$url" -o toplist.tmp

    (( "$(wc -l < toplist.tmp)" == 1000000 )) \
        || error 'Error downloading toplist.'

    # Expand toplist to include both root domains and subdomains
    mawk -v subdomains="$(mawk '{ print "^" $0 "\." }' \
        "$SUBDOMAINS" | paste -sd '|')" '{
        print
        if ($0 ~ subdomains) {
            sub(subdomains, "")
            print  # Print root domains
        }
    }' toplist.tmp | grep -P "^${DOMAIN_REGEX}$" | sort -u -o toplist.tmp
}

# Standardize the format of the given file.
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
        "$DEAD_DOMAINS"|"$PARKED_DOMAINS")
            # Remove duplicates, whitespaces, and convert to lowercase
            mawk '!seen[$0]++ { gsub(/ /, ""); print tolower($0) }' "$file" \
                > temp
            ;;
        "$PARKED_TERMS")
            # Convert to lowercase, sort, and remove duplicates
            mawk '{ print tolower($0) }' "$file" | sort -u -o temp
            ;;
        *.txt)
            # Remove whitespaces, convert to lowercase, sort, and remove
            # duplicates
            mawk '{ gsub(/ /, ""); print tolower($0) }' "$file" \
                | sort -u -o temp
            ;;
        *)
            return
            ;;
    esac

    [[ -f temp ]] && mv temp "$file"
}

# Format all files in the config and data directories.
format_files() {
    local file
    for file in config/* data/*; do
        format_file "$file"
    done
}

# Return the blacklist as a regex expression.
# Output:
#   Blacklisted domains as a regex expression
#   '_' if no blacklisted domains found to avoid errors with regex matching
get_blacklist() {
    if [[ ! -s "$BLACKLIST" ]]; then
        printf '_'
        return
    fi

    # Ensure periods are escaped twice to prevent
    # 'awk: warning: escape sequence \. treated as plain .' error
    mawk '{
        gsub(/\./, "\\\\\.")
        print "(^|\\\.)" $0 "$"
    }' "$BLACKLIST" | paste -sd '|'
}

# Return the whitelist as a regex expression.
# Output:
#   Whitelisted domains as a regex expression
#   '_' if no whitelisted domains found to avoid errors with regex matching
get_whitelist() {
    if [[ ! -s "$WHITELIST" ]]; then
        printf '_'
        return
    fi

    # Ensure periods are escaped twice to prevent
    # 'awk: warning: escape sequence \. treated as plain .' error
    mawk '{
        gsub(/\./, "\.")
        print
    }' "$WHITELIST" | paste -sd '|'
}

# Log domain processing events into the domain log.
# Input:
#   $1: domains to log either in a file or variable
#   $2: event type (dead, whitelisted, etc.)
#   $3: source
log_domains() {
    local domains

    # Check if a file or variable was passed
    if [[ -f "$1" ]]; then
        domains="$(<"$1")"
    else
        domains="$1"
    fi

    # Return if no domains were passed
    [[ -z "$domains" ]] && return

    mawk -v event="$2" -v source="$3" \
        -v time="$(TZ=Asia/Singapore date +"%H:%M:%S %d-%m-%y")" \
        '{ print time "," event "," $0 "," source }' \
        <<< "$domains" >> "$DOMAIN_LOG"
}

# Prune lines in the given file to keep its number of lines within the set
# limit.
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

# Send a Telegram notification with the given message.
# Input:
#   $TELEGRAM_CHAT_ID:   Telegram user Chat ID
#   $TELEGRAM_BOT_TOKEN: Telegram Bot Token
#   $1: message body
send_telegram() {
    curl -sSX POST \
        -H 'Content-Type: application/json' \
        -d "{\"chat_id\": \"${TELEGRAM_CHAT_ID}\", \"text\": \"${1}\"}" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -o /dev/null
}

# Check for configured entries in the review config file and add them to the
# whitelist/blacklist.
update_review_config() {
    # Add blacklisted entries to the blacklist and remove them from the review
    # config file
    mawk -F ',' '$4 == "y" && $5 != "y" { print $2 }' "$REVIEW_CONFIG" \
        | xargs -I {} sh -c "printf {} | sort -u - $BLACKLIST -o $BLACKLIST
        sed -i "/,{},/d" $REVIEW_CONFIG"

    # Add whitelisted entries to the whitelist after formatting to regex and
    # remove them from the review config file
    mawk -F ',' '$5 == "y" && $4 != "y" { print $2 }' "$REVIEW_CONFIG" \
        | tee >(mawk '{ gsub(/\./, "\."); print "^" $0 "$" }' \
        | sort -u - "$WHITELIST" -o "$WHITELIST") \
        | xargs -I {} sed -i "/,{},/d" "$REVIEW_CONFIG"
}

# Print error message and exit.
# Input:
#   $1: error message to print
error() {
    printf "\n\e[1;31m%s\e[0m\n\n" "$1" >&2
    exit 1
}

# Entry point

set -e

case "$1" in
    --convert-unicode)
        convert_unicode "$2"
        ;;
    --download-nrd-feed)
        download_nrd_feed
        ;;
    --download-toplist)
        download_toplist
        ;;
    --format-files)
        format_files
        ;;
    --get-blacklist)
        get_blacklist
        ;;
    --get-whitelist)
        get_whitelist
        ;;
    --log-domains)
        log_domains "$2" "$3" "$4"
        ;;
    --prune-lines)
        prune_lines "$2" "$3"
        ;;
    --send-telegram)
        send_telegram "$2"
        ;;
    --update-review-config)
        update_review_config
        ;;
    *)
        error "Invalid argument passed: $1"
        ;;
esac
