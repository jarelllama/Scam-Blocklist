### How the list is maintained

I run a script to search Google for specific search terms almost exclusively used in scam sites. The script returns a list of domains. The list is filtered in this order:
- checked against a whitelist (scam reporting sites, Reddit, genuine stores, etc.)
- duplicates are removed
- dead domains are removed
- the final list is compared against the Umbrella Toplist and domains on both lists are pointed out
- I manually check the potential false positives

### Goal

Identity newly created scam sites that use the same template as reported scam sites.
