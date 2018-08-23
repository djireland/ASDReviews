#!/usr/bin/bash

function CheckFor()
{
	   command -v ${1} >/dev/null 2>&1 || { echo -ne >&2 "Can't Find "; echo "${1}\n" ; exit 1;}
}

declare -a Tokens;

Tokens[0]="GAEiAggU:S:ANO1ljLtUJw"
Tokens[1]="GAEiAggo:S:ANO1ljIeRQQ"
Tokens[2]="GAEiAgg8:S:ANO1ljIM1CI"
Tokens[3]="GAEiAghQ:S:ANO1ljLxWBY"
Tokens[4]="GAEiAghk:S:ANO1ljJkC4I"
Tokens[5]="GAEiAgh4:S:ANO1ljJfGC4"
Tokens[6]="GAEiAwiMAQ==:S:ANO1ljL7Yco"
Tokens[7]="GAEiAwigAQ==:S:ANO1ljLMTko"
Tokens[8]="GAEiAwi0AQ==:S:ANO1ljJ2maA"
Tokens[9]="GAEiAwjIAQ==:S:ANO1ljIG2D4"
Tokens[10]="GAEiAwjcAQ==:S:ANO1ljJ9Wk0"
Tokens[11]="GAEiAwjwAQ==:S:ANO1ljLFcVI"


# ---- Main
export PATH=$PATH:`pwd`/utils/bin;
CheckFor grep
CheckFor fold 
CheckFor delimExtract
CheckFor hxnormalize
CheckFor hxselect
CheckFor paste
CheckFor tr
search=$1;
      HEA="-H Host: play.google.com"
      HEA="$HEA  -H User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:42.0) Gecko/20100101 Firefox/42.0"
      HEA="$HEA -H Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      HEA="$HEA -H Accept-Language: en-US,en;q=0.5"
      HEA="$HEA -H Accept-Encoding: gzip, deflate"
      HEA="$HEA -H Content-Type: application/x-www-form-urlencoded;charset=utf-8"
      HEA="$HEA -H Referer: https://play.google.com/store/apps/details?id=com.google.android.youtube"
      HEA="$HEA -H Content-Length: 76"
      HEA="$HEA -H Connection: keep-alive"
      HEA="$HEA -H Pragma: no-cache"
      HEA="$HEA -H Cache-Control: no-cache";

URL="https://play.google.com/store/search?q=${search}&c=apps&hl=en";

for ((i=0; i <= 11; i++)); do
  pagTok="${Tokens[i]}";
  raw=$(curl -d "pagTok=${pagTok}&start=5&num=5&numChildren=0&ipf=1&xhr=1" -X POST "${URL}" 2>/dev/null);
  pro=$(echo "${raw}" | hxnormalize 2>/dev/null);
  titles=$(echo "$pro"  | hxnormalize 2>/dev/null  | grep subtitle-container -A20 | delimExtract "title="  ">" | tr -d '\"');
  descri=$(echo "$pro"  | hxnormalize 2>/dev/null  | grep subtitle-container -A20 | delimExtract "description"  "<span");
  urls=$(echo "$pro"  | fold | delimExtract  "store/apps/details?id=" "\"" | sort | uniq);
  data=$(paste -d "|"  <(echo "$titles") <(echo "$descri") <(echo "$urls")  | tr -d '\"' | tr -s " ");
  echo "${urls}";
  sleep 1
done
rm -f out
