#!/bin/bash
query=$(/opt/homebrew/bin/choose -p "🔍 Search")
[ -z "$query" ] && exit 0
encoded=$(/usr/bin/python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$query")
open "https://www.google.com/search?q=$encoded"
