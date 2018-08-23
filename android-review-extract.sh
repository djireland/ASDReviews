#!/usr/bin/bash

getCursor() 
{
    exec < /dev/tty
    local oldstty=$(stty -g)
    stty raw -echo min 0
    echo -en "\033[6n" > /dev/tty
    IFS=';' read -r -d R -a pos
    stty $oldstty
    local row=$((${pos[0]:2} - 1))    # strip off the esc-[
    local col=$((${pos[1]} - 1))
    echo "${row} ${col}";
}

cecho() 
{
    local exp=$1;
    local color=$2;
    if ! [[ $color =~ '^[0-9]$' ]] ; then
       case $(echo $color | tr '[:upper:]' '[:lower:]') in
        black)   color=0 ;;
        red)     color=1 ;;
        green)   color=2 ;;
        yellow)  color=3 ;;
        blue)    color=4 ;;
        magenta) color=5 ;;
        cyan)    color=6 ;;
        white|*) color=7 ;; # white or invalid color
       esac
    fi
    tput setaf $color;
    echo -ne $exp;
    tput sgr0;
}

CheckFor()
{
    command -v ${1} >/dev/null 2>&1 || { echo -ne >&2 "Can't Find "; cecho "${1}\n" red; exit 1;}
}

echoerr () 
{
    echo "$@" 1>&2;
}

parseReview() 
{
    local in="$1";
    local out=$(echo -ne "${in}" | tr -d '\\' | hxnormalize -x 2>/dev/null);
    local reviews=$(echo "${out}" | grep "review-body" -A55 | hxcounter "<div class=\"review-body\">" "</div>" | tr -d '|');
    local titles=$(echo "${reviews}" |  delimExtract "review-title\">" "</span"| tr -d '|');
    local info=$(echo "${out}" | grep "review-info" -A55 | hxcounter "<div class=\"review-info\">" "</div>" | tr -d '|');
    local dates=$(echo "${info}" | delimExtract "review-date\">" "</span" | tr -d '|');
    local comme=$(echo "${reviews}" | delimExtract "</span>" "<div"| tr -d '|');    
    local stars=$(echo "${out}" | grep info-star-rating -A20 | hxcounter "<div class=\"review-info-star-rating\">" "</div>" |\
        delimExtract "Rated" "stars" | tr -s " " | tr -d '|');
    local ids=$(echo "{$info}" | tr -s ' ' | delimExtract "author-name\"> <a href=\"/store/people/details?id=" "</a>" | \
        tr  '\">' ' ' | tr -d "|");
    local id=$(echo "${ids}" | cut -d" " -f1 | tr -d "|");
    local names=$(echo "${ids}" | cut -d" " -f2- | tr -d "|");
    local data=$(paste -d "|" \
        <(echo "$id") <(echo "${names}") <(echo "$titles") <(echo "$stars") <(echo "$comme") <(echo "$dates"));

    if [[ ${#data} == "5" ]]; then
        return 1;
    fi
    echo "${data}" | tr -s " " ;
    return 0;
}

GetDetails() 
{
   local APP=$1;
   local URL="https://play.google.com/store/apps/details?id=${APP}"
   local in=$(curl  ${URL}  2>/dev/null);
   local time=$(shuf -i1-20 -n1);
   local out=$(echo -ne  "${in}"| hxnormalize 2>/dev/null);
   local namee=$(echo "$out"  | delimExtract "<title id=main-title>" "</title>" | tr -s ' ' | \
            sed 's/– Android Apps on Google Play//g' | tr  -d '|');
   local ratig=$(echo "$out"  | delimExtract "<div class=content itemprop=contentRating" "</div>" | tr  -d '|');
   local insta=$(echo "$out"  | delimExtract "<div class=content itemprop=numDownloads>" "</div>" | tr  -d '|');
   local lastu=$(echo "$out"  | delimExtract "<div class=content itemprop=datePublished>" "</div" | tr  -d '|');
   local versi=$(echo "$out"  | delimExtract "<div class=content itemprop=softwareVersion>" "</div" | tr  -d '|');
   local short=$(echo "$out"  | delimExtract "content=" ">" | grep name=Description | \
      tr -d '\"' | tr -s ' ' | sed 's/name=Description//g' | tr  -d '|');
   local longg=$(echo "$out" |  hxcounter "<div class=\"show-more-content text-body\"" "</div>" | \
            delimExtract "div jsname=C4s9Ed>" "</div>" | tr -s ' ' | tr ';' ',' | tr  -d '|');
   local compa=$(echo "$out"  | grep "meta content=\"/store/apps/developer?id=" | delimExtract "?id=" "\"" | tr  -d '|');
   local files=$(echo "$out" | delimExtract "<div class=content itemprop=fileSize>" "</div>" | tr  -d '|');
   local opers=$(echo "$out" | delimExtract "<div class=content itemprop=operatingSystems>" "</div>" | tr  -d '|');
   local price=$(echo "$out" | grep  "itemprop=price" | delimExtract "<meta content=" "itemprop=price>" | \
            tr -d '\"' | tr  -d '|');
   local whats=$(echo "$out" | tr -d '\"' |  delimExtract "<div class=recent-change>" "</div>" | \
            tr -s ' ' | tr '\n' ';' | tr  -d '|');
   local email=$(echo "$out" | delimExtract ">Email" "</a>" | tr  -d '|');
   local hasIn=$(echo "$out" | grep "Offers in-app purchases" >/dev/null && echo "YES" || echo "NO");
   local categ=$(echo "$out" | hxcounter "<a class=\"document-subtitle category" "</div>" | \
       delimExtract "/store/apps/category/" "\">" | tr -d '|');

   local count=$(echo "$out" | grep "ratingCount" | delimExtract "meta content=" "itemprop=ratingCount");
   local value=$(echo "$out" | grep "ratingValue" | delimExtract "meta content=" "itemprop=ratingValue");

   local DATA="${APP}  | ${namee} | ${price} |  ${lastu} | ${versi} | ${insta} | ${value} | ${count} |${compa} | ${email}";
         DATA="${DATA} | ${short} | ${longg} | ${ratig}  | ${files} | ${opers} | ${whats} | ${hasIn}";
         DATA="${DATA} | ${categ}";
   echo "${DATA}";
   sleep ${time};
}


GetFirstPage() 
{
    local APP=$1;
    local page=$(curl "https://play.google.com/store/apps/details?id=${APP}" 2>/dev/null);
    local in=$(echo "${page}");
    local first=$(parseReview "$in");
    echo "${first}";
}

GetReviews() 
{
    local APP=$1;
    local maxPages=${2:-250};
    local URL="https://play.google.com/store/getreviews?authuser=0";
    local PAGES=1;
    local HEA="-H Host: play.google.com"
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

   for ((i=1; i<${maxPages}; i++)); do
        in=$(curl "${HEA}" -d "reviewType=0&pageNum=${i}&id=${APP}&reviewSortOrder=1&xhr=1" -X POST "${URL}" 2>/dev/null);
        local tme=$(shuf -i1-20 -n1);    
        sleep ${tme};
        local review=$(parseReview "$in");
        if [[ ${#review} -lt "25" ]]; then 
            break;
        fi
        echo "${review}";
   done
}

createTable() 
{
    local database=$1;
    if [[ -f ${database}.db ]]; then
        return
    fi
 
    sqlite3 ${database}.db  "CREATE TABLE Details (
    ID              INTEGER PRIMARY KEY,
    AppID           TEXT NOT NULL,
    Name            TEXT,
    Category        TEXT,
    Price           TEXT,
    LastUpdated     TEXT,
    CurrentVersion  TEXT, 
    Installs        TEXT,
    Rating          TEXT,
    RatingCount     TEXT,
    Developer       TEXT,
    DeveloperEmail  TEXT, 
    Short           TEXT, 
    Long            TEXT,
    ContentRating   TEXT,
    FileSize        TEXT,
    OperatingSystem TEXT,
    WhatsNew        TEXT,
    InAppPurchases  TEXT,
    InsertDate      TEXT,
    Hash TEXT);";
 
    sqlite3 ${database}.db  "CREATE TABLE Reviews (
    ID          INTEGER PRIMARY KEY, 
    AppID       TEXT NOT NULL, 
    UserID      TEXT,
    UserName    TEXT,
    ReviewTitle TEXT, 
    Rating      TEXT,
    Comments    TEXT,
    Date        TEXT,
    InsertDate  TEXT,
    Hash        TEXT);";
}

AddDetailsToDatabase() 
{
    local database=$1;
    local appID=$2;
    local details=$3
    if [[ ! -f ${database}.db ]]; then
        echo "Database Doesn't Exist!";
        exit;
    fi
   
    local N=$(echo "${details}" | wc -l);
    local I=0;

    while read line; do 
        local appid=$(echo -ne "$line" | cut -d"|" -f1  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local namee=$(echo -ne "$line" | cut -d"|" -f2  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local price=$(echo -ne "$line" | cut -d"|" -f3  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local lastu=$(echo -ne "$line" | cut -d"|" -f4  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local currv=$(echo -ne "$line" | cut -d"|" -f5  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local insta=$(echo -ne "$line" | cut -d"|" -f6  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local rativ=$(echo -ne "$line" | cut -d"|" -f7  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local ratic=$(echo -ne "$line" | cut -d"|" -f8  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local devel=$(echo -ne "$line" | cut -d"|" -f9  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local email=$(echo -ne "$line" | cut -d"|" -f10  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local short=$(echo -ne "$line" | cut -d"|" -f11  | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local longd=$(echo -ne "$line" | cut -d"|" -f12 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local ratin=$(echo -ne "$line" | cut -d"|" -f13 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local files=$(echo -ne "$line" | cut -d"|" -f14 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local opers=$(echo -ne "$line" | cut -d"|" -f15 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
        local whats=$(echo -ne "$line" | cut -d"|" -f16 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local hasIn=$(echo -ne "$line" | cut -d"|" -f17 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local categ=$(echo -ne "$line" | cut -d"|" -f18 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g' | tr -s ' ');
        local insda=$(date);
        local hashV=$(echo "${rativ}${ratic}${appid}${price}${lastu}${currv}${inst}${ratin}${opers}"\
            | md5sum | awk '{print $1}'); 
        
        if [[ ${Categories} ]]; then
            local Want="No";
            IFS="+";
            for c in ${Categories}; do
                echo "$categ" | grep $c >/dev/null; 
                if [[ $? == "0" ]]; then 
                    Want="Yes";
                    break;
                fi
            done
            IFS=" ";
            if [[ $Want == "No" ]]; then
                continue;
            fi
        fi

        local cmd="SELECT EXISTS(SELECT * FROM Details WHERE"; 
              cmd="${cmd} hash='${hashV}' LIMIT 1)";
        local exists=$(sqlite3 ${database}.db "${cmd}");
        if [[ ${exists} == "1" ]]; then 
           continue;
        else 
            local cmd="insert into Details";
            cmd="$cmd (AppID, Name, Category, Price, LastUpdated, CurrentVersion, Installs,Rating, RatingCount,"
            cmd="$cmd  Developer, DeveloperEmail,";
            cmd="$cmd  Short, Long, FileSize, ContentRating, OperatingSystem, WhatsNew, InAppPurchases, InsertDate, Hash)";
            cmd="$cmd  values (";
            cmd="$cmd'${appid}','${namee}','${categ}','${price}','${lastu}','${currv}','${insta}','${rativ}','${ratic}',";
            cmd="$cmd'${devel}','${email}','${short}','${longd}','${files}','${ratin}',";
            cmd="$cmd'${opers}','${whats}','${hasIn}','${insda}','${hashV}');";
            sqlite3 ${database}.db "${cmd}";
            echo -ne "Inserted Details for ";
            cecho " ${appid} " cyan;
            echo -ne " $(date)\n";
            I=$((I+1));
        fi
   done <<< "$details";
}

AddReviewsToDatabase() 
{
    local database=$1;
    local appID=$2;
    local reviews=$3;

    if [[ ! -f ${database}.db ]]; then
        echo "Database Doesn't Exist!";
        exit;
    fi
   
    local I=0;
    local N=$(echo "${reviews}" | wc -l);
    
    while read line; do
       local userID=$(     echo -ne  "$line" | cut -d"|" -f1 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
       local userName=$(   echo -ne  "$line" | cut -d"|" -f2 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
       local reviewTitle=$(echo -ne  "$line" | cut -d"|" -f3 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
       local rating=$(     echo -ne  "$line" | cut -d"|" -f4 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
       local comments=$(   echo -ne  "$line" | cut -d"|" -f5 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
       local date=$(       echo -ne  "$line" | cut -d"|" -f6 | tr -d "\'" | sed -e 's/^[ \t]*//' |  sed 's/\s*$//g');
       local insertDate=$(date);
       local hashV=$(echo "${reviewTitle}${rating}${userID}${date}" | md5sum | awk '{print $1}'); 
       local cmd="SELECT EXISTS(SELECT * FROM Reviews WHERE"; 
             cmd="${cmd} hash='${hashV}' LIMIT 1)";
       local exists=$(sqlite3 ${database}.db "${cmd}");
       if [[ ${exists} == "1" ]]; then 
            # echo "Already Have Review ";
        continue;
    else 
        local cmd="insert into Reviews (AppID, UserID, UserName, ReviewTitle, Rating, Comments, Date, InsertDate, Hash) ";  
              cmd="$cmd values(";
              cmd="$cmd '${appID}', '${userID}', '${userName}',"
              cmd="$cmd '${reviewTitle}','${rating}', '${comments}','${date}','${insertDate}','${hashV}');";
              sqlite3 ${database}.db "${cmd}";
              I=$((I+1));
    fi
    done <<< "${reviews}"

    if [[ $I != "0" ]]; then
        echo -ne "Added $I new reviews for "
        cecho " ${appID} " cyan;
        echo -ne " -> ";
        cecho " ${database}.db " cyan
        echo -ne " $(date)\n";
    fi 
}

CheckDepend() 
{
    CheckFor grep
    CheckFor sqlite3
    CheckFor fold 
    CheckFor sort
    CheckFor wc
    CheckFor cat
    CheckFor sed
    CheckFor cut
    CheckFor basename
    CheckFor uniq
    CheckFor delimExtract
    CheckFor hxnormalize
    CheckFor hxselect
    CheckFor hxcounter
    CheckFor paste
    CheckFor tr
}

ParseArguments() 
{
    while [[ $# > 0 ]]; do
        key=$1;
        case $key in 
            -d|--directory)
                URLDirectory="$2";
                shift 2
                ;;
            --id)
                URLIN="$2";
                shift 2;
                ;;
            --sql)
                SQL="$2";
                shift 2;
                ;;
            -o|--out)
                OutDatabase="$2";
                shift 2;
                ;;
            --details)
                GetDetails="YES";
                shift 1
                ;;
            --reviews)
                GetReviews="YES";
                shift 1
                ;;
            -c|--categories)
                Categories="$2";
                shift 2;
                ;;
            *)
                echo "Unknown Option $key";
                exit
            ;;
        esac
    done
}

main()
{   # Main Routine ------------------------------------------------------------------------
    export PATH=$PATH:`pwd`/utils/bin;
    CheckDepend;
    if [[ $# == "0" ]]; then
        echo "Usage monitor.sh -d URLDirectiry --reviews --details";
        exit;
    fi
      
    ParseArguments $@;  

    if [[ $Categories ]]; then
        echo -ne "Filtering Apps not in these categories ";
        cecho " ${Categories}\n" red;
    fi

    local files="";
    if [[ ${URLDirectory} ]]; then
        if [[ ! -d ${URLDirectory} ]]; then
            echo "URL Directory Doesn't Exist!";
            exit;
        fi
        files=$(ls ./${URLDirectory} | shuf);
    fi
    
    if [[ ${SQL} ]]; then
        if [[ ! -f ${SQL} ]]; then
            echo "SQL Database Doesn't Exist"; 
            exit
        fi
        files="${files}"$(sqlite3 "${SQL}" "select AppId From Details" | shuf);
    fi

    if [[ ${URLIN} ]]; then
        files="${files}${URLIN}";
    fi

    files=$(echo "${files}" | sort | uniq);
    
    while read f; do 
        local name=$(basename $f);
        createTable ${name};
        
        if [[ $URLDirectory ]]; then 
            local URLs=$(cat ${URLDirectory}/$f | sort | uniq | tr -s '\n' | tr -s ' ');
        else 
            local URLS=$f; 
        fi
        local maxPage=250;
        while read line; do
            local url=$(echo $line| cut -d"=" -f2);
            if [[ $url ]]; then
                if [[ $GetDetails ]]; then
                    local details="$(GetDetails "${url}")";
                    AddDetailsToDatabase "${name}" "${url}" "${details}";
                fi

                if [[ $GetReviews ]]; then 
                    local reviews="$(GetFirstPage "${url}")$(GetReviews "${url}" "${maxPage}")";
                    AddReviewsToDatabase "${name}" "${url}" "${reviews}";
                fi
            fi
        done <<< "$URLs"
    done <<< "${files}"
}


main $@; # Program Entry Point

