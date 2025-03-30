#!/bin/bash

# Run a source function to retrieve the results from the source.
# Input:
#   $1: source function to run
# Output:
#   results.tmp (can contain URLs and square brackets)

readonly PHISHING_TARGETS='config/phishing_detection.csv'
# '[\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]' matches the root domain and subdomains
# '[\p{L}\p{N}]' matches single character subdomains
# '\[?\.\]?' matches periods optionally enclosed by square brackets
# '[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]' matches the TLD (TLDs can not start with a number)
readonly DOMAIN_REGEX='(?:([\p{L}\p{N}][\p{L}\p{N}-]*[\p{L}\p{N}]|[\p{L}\p{N}])\[?\.\]?)+[\p{L}}][\p{L}\p{N}-]*[\p{L}\p{N}]'

# Input:
#   $1: URL to scrape (default is $URL)
# Output:
#   webpage HTML
CURL() {
    curl -sSLZ --retry 2 --retry-all-errors "${1:-$URL}"
}

165antifraud() {
    # Last checked: 29/03/25
    URL='https://165.npa.gov.tw/api/article/subclass/3'
    CURL \
        | jq --arg year "$(date +%Y)" '.[] | select(.publishDate | contains($year)) | .content' \
        | grep -Po "\\\">\K${DOMAIN_REGEX}" > results.tmp
}

aa419() {
    # Last checked: 29/03/25
    URL='https://api.aa419.org/fakesites'
    curl -sSL --retry 2 --retry-all-errors -H "Auth-API-Id:${AA419_API_ID}" \
        "${URL}/0/500?fields=Domain" \
        | grep -Po "Domain\":\"\K${DOMAIN_REGEX}" > results.tmp
}

behindmlm() {
    # Last checked: 29/03/25
    URL='https://behindmlm.com'
    CURL "${URL}/page/[1-15]" \
        | grep -iPo "(&#8220;|<li>|; |: |and )\K${DOMAIN_REGEX}" > results.tmp
}

bugsfighter() {
    # Last checked: 29/03/25
    URL='https://www.bugsfighter.com/blog'
    CURL "${URL}/page/[1-50]" | grep -iPo "remove \K${DOMAIN_REGEX}" \
        > results.tmp
}

chainabuse() {
    # Last checked: 03/03/25
    URL='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/chainabuse.txt'
    CURL > results.tmp
}

coi.gov.cz() {
    # Last checked: 29/03/25
    URL='https://coi.gov.cz/pro-spotrebitele/rizikove-e-shopy'
    CURL | mawk '/<p class = "list_titles">/ { getline; getline; print }' \
        | grep -Po "<span>(https?://)?\K$DOMAIN_REGEX" > results.tmp
}

crypto_scam_tracker() {
    # Last checked: 29/03/25
    # TODO: match column 4 and 5 lines

    URL='https://dfpi.ca.gov/consumers/crypto/crypto-scam-tracker'
    CURL | mawk '
        # Note that matching lines between column 4 and 5 is not inclusive of
        # the column 4 and 5 lines themselves
        /"column-3"/ {
            block = 1;
            next
        }
        /<\/tr>/ {
            block = 0
        }
        block
        ' | grep -Po "(https?://)?\K${DOMAIN_REGEX}" > results.tmp
}

dga_detector() {
    # Last checked: 28/03/25
    URL='https://github.com/jarelllama/dga_detector/archive/refs/heads/master.zip'

    # Install DGA Detector and dependencies
    CURL > dga_detector.zip
    unzip -q dga_detector.zip
    pip install -q tldextract

    # Keep only non-Punycode NRDs with 16 or more characters (including period
    # and TLD)
    mawk 'length($0) >= 16 && !/xn--/' nrds.tmp > domains.tmp

    cd dga_detector-master

    # Set the detection threshold. DGA domains fall below this threshold.
    # A lower threshold lowers the domain yield and reduces false positives.
    sed -i "s/threshold = model_data\['thresh'\]/threshold = 0.0008/" \
        dga_detector.py

    # Run DGA Detector on the remaining NRDs
    python3 dga_detector.py -f ../domains.tmp > /dev/null

    # Extract DGA domains from the JSON output
    jq -r 'select(.is_dga == true) | .domain' dga_domains.json > ../results.tmp

    cd ..

    rm -r dga_detector* domains.tmp
}

dnstwist_() {
    # Last checked: 30/03/25
    local tlds results

    command -v dnstwist > /dev/null || pip install -q dnstwist

    # Get TLDs from the NRD feed
    tlds="$(mawk -F '.' '!seen[$NF]++ { print $NF }' nrds.tmp)"

    # Loop through the phishing targets
    mawk -F ',' '$4 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Run dnstwist and append TLDs
        results="$(mawk -v tlds="$tlds" '
            {
                sub(/\.com$/, "")
                n = split(tlds, tldArray, " ")
                for (i = 1; i <= n; i++) {
                    print $0"."tldArray[i]
                }
            }' <<< "$(dnstwist "${target}.com" -f list)" | sort -u)"

        # Get matching NRDs and update counts for the target
        mawk -v target="$target" -v results="$(
            comm -12 <(printf "%s" "$results") nrds.tmp \
                | tee -a results.tmp \
                | wc -l
            )" -F ',' '
            BEGIN { OFS = "," }
            $1 == target {
                $2 += results
                $3 += 1
            }
            { print }
        ' "$PHISHING_TARGETS" > temp
        mv temp "$PHISHING_TARGETS"
    done
}

emerging_threats() {
    # Last checked: 28/03/25
    URL='https://rules.emergingthreats.net/open/suricata-5.0/emerging.rules.zip'
    CURL > rules.zip
    unzip -q rules.zip -d rules

    # Ignore rules with specific payload keywords. See here:
    # https://docs.suricata.io/en/suricata-6.0.0/rules/payload-keywords.html
    # Note 'endswith' is accepted as those rules tend to be wildcard matches of
    # root domains (leading periods are removed for those rules).
    local RULE
    for RULE in emerging-adware_pup emerging-coinminer emerging-exploit_kit \
        emerging-malware emerging-mobile_malware emerging-phishing; do
        cat "rules/rules/${RULE}.rules"
    done | mawk '/dns[\.|_]query/ &&
        !/^#|content:!|startswith|offset|distance|within|pcre/' \
        | grep -Po "content:\"\.?\K${DOMAIN_REGEX}" > results.tmp

    rm -r rules*
}

fakewebshoplisthun() {
    # Last checked: 28/03/25
    URL='https://raw.githubusercontent.com/FakesiteListHUN/FakeWebshopListHUN/refs/heads/main/fakewebshoplist'
    CURL | grep -Po "^(\|\|)?\K${DOMAIN_REGEX}(?=\^?$)" > results.tmp
}

greatis() {
    # Last checked: 28/03/25
    URL='https://greatis.com/unhackme/help/category/remove'
    CURL "${URL}/page/[1-15]" | grep -iPo "remove \K${DOMAIN_REGEX}" \
        > results.tmp
}

gridinsoft() {
    # Last checked: 17/02/25
    URL='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/gridinsoft.txt'
    CURL > results.tmp
}

jeroengui() {
    # Last checked: 28/03/25
    URL='https://file.jeroengui.be'
    url_shorterners='https://raw.githubusercontent.com/hagezi/dns-blocklists/refs/heads/main/adblock/whitelist-urlshortener.txt'

    # Get domains from the various lists and exclude link shorteners
    curl -sSLZ --retry 2 --retry-all-errors \
        "${URL}/phishing/last_month.txt" \
        "${URL}/malware/last_month.txt" \
        "${URL}/scam/last_month.txt" \
        | grep -Po "^https?://\K${DOMAIN_REGEX}" \
        | grep -vF "$(CURL "$url_shorterners" \
        | grep -Po "\|\K${DOMAIN_REGEX}")" > results.tmp

    # Get matching NRDs for the light version. Note that the NRD feed does not
    # contain Unicode
    comm -12 <(sort results.tmp) nrds.tmp > jeroengui_nrds.tmp
}

jeroengui_nrds() {
    # Last checked: 29/12/24
    # Only includes domains found in the NRD feed for the light version
    mv jeroengui_nrds.tmp results.tmp
}

malwarebytes() {
    # Last checked: 28/03/25
    URL='https://www.malwarebytes.com/blog/detections'
    CURL | grep -Po ">\K${DOMAIN_REGEX}(?=</a>)" | mawk '!/[A-Z]/' \
        > results.tmp
}

malwareurl() {
    # Last checked: 17/02/25
    URL='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/malwareurl.txt'
    CURL > results.tmp
}

pcrisk() {
    # Last checked: 28/03/25
    URL='https://www.pcrisk.com/removal-guides'
    CURL "${URL}?start=[0-50]0" \
        | mawk '/article class/ { getline; getline; getline; getline; print }' \
        | grep -Po ">\K${DOMAIN_REGEX}" > results.tmp
}

phishing_nrds() {
    # Last checked: 30/03/25
    local pattern escaped_target regex

    # Loop through the phishing targets
    mawk -F ',' '$8 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Get the target regex expression
        pattern="$(mawk -v target="$target" -F ',' '
            $1 == target { print $5 }' "$PHISHING_TARGETS")"
        escaped_target="${target//[.]/\\.}"
        regex="${pattern//&/${escaped_target}}"

        # Get matching NRDs and update counts for the target
        # awk is used here instead of mawk for compatibility with the regex
        # expressions.
        mawk -v target="$target" -v results="$(
            awk "/${regex}/" nrds.tmp \
                | sort -u \
                | tee -a results.tmp \
                | wc -l
            )" -F ',' '
            BEGIN { OFS = "," }
            $1 == target {
                $6 += results
                $7 += 1
            }
            { print }
        ' "$PHISHING_TARGETS" > temp
        mv temp "$PHISHING_TARGETS"
    done
}

phishstats() {
    # Last checked: 30/03/25
    URL='https://phishstats.info/phish_score.csv'
    CURL | grep -Po ",\"https?://\K${DOMAIN_REGEX}" > results.tmp
}

puppyscams() {
    # Last checked: 30/02/25
    URL='https://puppyscams.org'
    CURL "${URL}/?page=[1-15]" | grep -Po " \K${DOMAIN_REGEX}(?=</h4></a>)" \
        > results.tmp
}

safelyweb() {
    # Last checked: 30/03/25
    URL='https://safelyweb.com/scams-database'
    CURL "${URL}/?per_page=[1-30]" \
        | grep -iPo "suspicious website</div> <h2 class=\"title\">\K${DOMAIN_REGEX}" \
        > results.tmp
}

scamadviser() {
    # Last checked: 30/03/25
    URL='https://www.scamadviser.com/articles'
    CURL "${URL}?p=[1-15]" | grep -Po "[A-Z0-9][-.]?${DOMAIN_REGEX}" \
        > results.tmp
}

scamdirectory() {
    # Last checked: 29/03/25
    URL='https://scam.directory/category'
    # head -n causes grep broken pipe error
    CURL | grep -Po "<span>\K${DOMAIN_REGEX}(?=<br>)" > results.tmp
}

scamminder() {
    # Last checked: 29/03/25
    URL='https://scamminder.com/websites'
    # There are about 150 new pages daily
    CURL "${URL}/page/[1-1000]" \
        | mawk '/Trust Score :  strongly low/ { getline; print }' \
        | grep -Po "class=\"h5\">\K${DOMAIN_REGEX}" > results.tmp
}

scamscavenger() {
    # Last checked: 10/03/25
    URL='https://raw.githubusercontent.com/jarelllama/Blocklist-Sources/refs/heads/main/scamscavenger.txt'
    CURL > results.tmp
}

scamtracker() {
    # Last checked: 29/03/25
    URL='https://scam-tracker.net/category/crypto-scams'
    local -a review_urls

    # Collate the review URLs into an array
    mapfile -t review_urls < <(CURL "${URL}/page/[1-100]" \
        | grep -Po '"headline"><a href="\Khttps://scam-tracker.net/crypto-scams/.*(?=/" rel="bookmark">)')

    # The array does not pass to CURL() properly
    curl -sSLZ --retry 2 --retry-all-errors "${review_urls[@]}" \
        | mawk '/Website<\/div>/ { getline; print }' \
        | grep -Po "${DOMAIN_REGEX}" > results.tmp
}

unit42() {
    # Last checked: 29/03/25
    URL='https://github.com/PaloAltoNetworks/Unit42-timely-threat-intel/archive/refs/heads/main.zip'
    CURL > unit42.zip
    unzip -q unit42.zip -d unit42

    grep -hPo "\[:\]//\K${DOMAIN_REGEX}|^- \K${DOMAIN_REGEX}" \
        unit42/*/"$(date +%Y)"* > results.tmp

    rm -r unit42*
}

urlcrazy() {
    # Last checked: 30/03/25
    local results

    URL='https://github.com/urbanadventurer/urlcrazy/archive/refs/heads/master.zip'

    # Install URLCrazy and dependencies
    CURL > urlcrazy.zip
    unzip -q urlcrazy.zip
    command -v ruby > /dev/null || apt-get install -qq ruby ruby-dev
    # sudo is needed for gem
    sudo gem install --silent json colorize async async-dns async-http

    # Loop through the phishing targets
    mawk -F ',' '$4 == "y" { print $1 }' "$PHISHING_TARGETS" \
        | while read -r target; do

        # Run URLCrazy (bash does not work)
        # Note that URLCrazy appends possible TLDs
        results="$(./urlcrazy-master/urlcrazy -r "${target}.com" -f CSV \
            | mawk -F ',' 'NR > 3 { gsub(/"/, "", $2); print $2 }' | sort -u)"

        # Get matching NRDs and update counts for the target
        mawk -v target="$target" -v results="$(
            comm -12 <(printf "%s" "$results") nrds.tmp \
                | tee -a results.tmp \
                | wc -l
            )" -F ',' '
            BEGIN { OFS = "," }
            $1 == target {
                $2 += results
                $3 += 1
            }
            { print }
        ' "$PHISHING_TARGETS" > temp
        mv temp "$PHISHING_TARGETS"
    done

    rm -r urlcrazy*
}

viriback_tracker() {
    # Last checked: 29/03/25
    URL='https://tracker.viriback.com/dump.php'
    CURL | mawk -v year="$(date +%Y)" -F ',' '$4 ~ year { print $2 }' \
        | grep -Po "^(https?://)?\K${DOMAIN_REGEX}" > results.tmp
}

vzhh.de() {
    # Last checked: 29/03/25
    URL='https://www.vzhh.de/themen/einkauf-reise-freizeit/einkauf-online-shopping/fake-shop-liste-wenn-guenstig-richtig-teuer-wird'
    CURL | mawk '/Shops in alphabetischer Reihenfolge/' \
        | grep -Po "${DOMAIN_REGEX}" > results.tmp
}

wipersoft() {
    # Last checked: 29/03/25
    URL='https://www.wipersoft.com/blog'
    CURL "${URL}/page/[1-25]" \
        | mawk '/<div class="post-content">/ { getline; print }' \
        | grep -Po "${DOMAIN_REGEX}" > results.tmp
}

# Entry point

set -e

[[ -f results.tmp ]] && rm results.tmp

"$1" || true
