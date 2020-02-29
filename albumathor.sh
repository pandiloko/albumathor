#!/bin/bash
#vim: set softtabstop=4 shiftwidth=4 expandtab
# ALBUMATHOR

create_database (){

sqlite3 $DB_FILE <<EOF

BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS '$MAIN_TABLE' (
    'SourceFile' TEXT,
    'Aperture' TEXT,
    'CreateDate' TEXT,
    'DateTimeOriginal' TEXT,
    'Directory relapath' TEXT,
    'ExifImageHeight' TEXT,
    'ExifImageWidth' TEXT,
    'ExifToolVersion' TEXT,
    'ExifVersion' TEXT,
    'ExposureCompensation' TEXT,
    'ExposureMode' TEXT,
    'ExposureProgram' TEXT,
    'ExposureTime' TEXT,
    'FileName' TEXT,
    'FileSize' TEXT,
    'FileType' TEXT,
    'FileTypeExtension' TEXT,
    'Flash' TEXT,
    'FNumber' TEXT,
    'FocalLength' TEXT,
    'FocalLength35efl' TEXT,
    'FOV' TEXT,
    'GPSAltitude' TEXT,
    'GPSAltitudeRef' TEXT,
    'GPSDateStamp' TEXT,
    'GPSDateTime' TEXT,
    'GPSDestBearing' TEXT,
    'GPSDestBearingRef' TEXT,
    'GPSHPositioningError' TEXT,
    'GPSImgDirection' TEXT,
    'GPSImgDirectionRef' TEXT,
    'GPSLatitude' TEXT,
    'GPSLatitudeRef' TEXT,
    'GPSLongitude' TEXT,
    'GPSLongitudeRef' TEXT,
    'GPSPosition' TEXT,
    'GPSSpeed' TEXT,
    'GPSSpeedRef' TEXT,
    'GPSTimeStamp' TEXT,
    'HyperfocalDistance' TEXT,
    'ImageHeight' TEXT,
    'ImageSize' TEXT,
    'ImageWidth' TEXT,
    'ISO' TEXT,
    'LensInfo' TEXT,
    'LensMake' TEXT,
    'LensModel' TEXT,
    'LightValue' TEXT,
    'Make' TEXT,
    'Megapixels' TEXT,
    'MIMEType' TEXT,
    'Model' TEXT,
    'Orientation' TEXT,
    'Quality' TEXT,
    'ShutterSpeed' TEXT,
    'WhiteBalance' TEXT,
    'ByteSize' INTEGER,
    'BLAKE2'    TEXT NOT NULL PRIMARY KEY,
    'RealDate' TEXT,
    'ALBUMID' INTEGER
);

CREATE TABLE IF NOT EXISTS '$LOCATIONS_TABLE' (
    'city' TEXT,
    'state' TEXT,
    'country' TEXT,
    'suburb' TEXT,
    'postcode' TEXT,
    'display' TEXT,
    'BLAKE2' TEXT NOT NULL PRIMARY KEY,
    FOREIGN KEY (BLAKE2) REFERENCES $MAIN_TABLE (BLAKE2)
            ON DELETE CASCADE ON UPDATE NO ACTION
);

CREATE TABLE IF NOT EXISTS '$ALBUM_TABLE' (
    'NAME' TEXT NOT NULL,
    'ALBUMID' INTEGER PRIMARY KEY
);

COMMIT;
EOF
}

recreate_album_table(){
    sqlite3 $DB_FILE <<EOF
BEGIN TRANSACTION;
DROP TABLE IF EXISTS $ALBUM_TABLE;
CREATE TABLE IF NOT EXISTS '$ALBUM_TABLE' (
    'NAME' TEXT NOT NULL,
    'ALBUMID' INTEGER PRIMARY KEY
);
COMMIT;
EOF
}

create_gps_cache(){
    sqlite3 $GPS_FILE <<EOF

BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS '$GPS_TABLE' (
    'LATITUDE' TEXT NOT NULL,
    'LONGITUDE' TEXT NOT NULL,
    'RAW' TEXT,
    'CITY' TEXT,
    'STATE' TEXT,
    'COUNTRY' TEXT,
    'SUBURB' TEXT,
    'POSTCODE' TEXT
);
COMMIT;
EOF
}

exists_checksum (){
    # $1 -> db
    # $2 -> source blake2 checksum
    local sum=$2
    #search in db
    local out=$(sqlite3 -batch $DB_FILE "select * from $1 where BLAKE2='$sum';")

    [ -z "$out" ] && return 404
    return 0
}

exists_file(){
    # $1 -> source filename and path
    # $2 -> source file size in bytes
    local filename=$(basename -- "$1")
    local size=$2
    local out=$(sqlite3 -batch $DB_FILE "select SourceFile from $MAIN_TABLE where ByteSize=$size and FileName='$filename';")
    [ -z "$out" ] && return 404
    return 0
}

insert (){
    local tuple="$1"
    local bytesize="$2"
    local blake2="$3"

    if exists_checksum fotos $blake2 ;then
        return 302
    else
        echo "inserting $tuple,$bytesize,$blake2"
        sqlite3 -batch $DB_FILE <<EOF
insert into $MAIN_TABLE values($tuple,$bytesize,'$blake2','-');
EOF
	#FIX some data:

        IFS=',' read -ra values <<< "$tuple"
	sqlite3 -batch $DB_FILE  " UPDATE $MAIN_TABLE SET GPSLatitude='$(convert_lalong $values[31]), GPSLongitude=$(convert_lalong $values[33]) where blake2='$blake2';"
        local out=$(sqlite3 -batch $DB_FILE  "SELECT * from $MAIN_TABLE where blake2='$blake2';")
        IFS='|' read -ra tuple <<< "$out"

        # IFS=',' read -ra values <<< "$tuple"
	# values=( "${values[@]//\'/}" )
	# values=( "${values[@]# }" )

        
	local createdate="${tuple[2]}"
	local datetimeoriginal="${tuple[3]}"
	local filename="${tuple[13]}"
	local gpsdatestamp="${tuple[24]}"
	local gpsdatetime="${tuple[25]}"
        local gpslatitude=$(dmg2dd_lat "${tuple[31]}")
        local gpslongitude=$(dmg2dd_long "${tuple[33]}")
	local gpstimestamp="${tuple[39]}"

	#FIX DATE
	
	if [[ $datetimeoriginal != '-' ]] && [[ $datetimeoriginal != 'null' ]] && [ -n "$datetimeoriginal" ];then
		realdate=$datetimeoriginal
	elif [[ $gpsdatetime != '-' ]] && [[ $gpsdatetime != 'null' ]] && [ -n "$gpsdatetime" ];then
		realdate=$gpdsatetime 
		#check format and convert???
	elif [[ $createdate != '-' ]] && [[ $createdate != 'null' ]] && [ -n "$createdate" ];then
		realdate=$createdate
	else 
		#else compare other dates or filename
                local regex='((1|2)[[:digit:]]{3})(\-|\.|:)?([[:digit:]]{2})(\-|\.|:)?([[:digit:]]{2})[^[:digit:]]+([0-2][0-9])(\-|\.|:)?([0-5][0-9])(\-|\.|:)?([0-5][0-9])'
		# local regex='(1|2)[[:digit:]]{3}(\-|\.|:)?[[:digit:]]{2}(\-|\.|:)?[[:digit:]]{2}[^[:digit:]]+[0-2][0-9](\-|\.|:)?[0-5][0-9](\-|\.|:)?[0-5][0-9]'
		if [[ "$filename" =~ $regex ]];then
			echo ${BASH_REMATCH[0]}
                        echo ${BASH_REMATCH[@]}
			#should probably work just with index 0 but 
			realdate=$(date --date "${BASH_REMATCH[1]}/${BASH_REMATCH[4]}/${BASH_REMATCH[6]} ${BASH_REMATCH[7]}:${BASH_REMATCH[9]}:${BASH_REMATCH[11]}" +"%s" )
		fi
#Stackoverflow regex for dd/mm/yyyy, dd-mm-yyyy or dd.mm.yyyy
#^(?:(?:31(\/|-|\.)(?:0?[13578]|1[02]))\1|(?:(?:29|30)(\/|-|\.)(?:0?[13-9]|1[0-2])\2))(?:(?:1[6-9]|[2-9]\d)?\d{2})$|^(?:29(\/|-|\.)0?2\3(?:(?:(?:1[6-9]|[2-9]\d)?(?:0[48]|[2468][048]|[13579][26])|(?:(?:16|[2468][048]|[3579][26])00))))$|^(?:0?[1-9]|1\d|2[0-8])(\/|-|\.)(?:(?:0?[1-9])|(?:1[0-2]))\4(?:(?:1[6-9]|[2-9]\d)?\d{2})$
#My own naive regex for YYYY/mm/dd HH:MM:ss with dashes, colon or slash
#(1|2)[[:digit:]]{3}(\-|\.|:)?[[:digit:]]{2}(\-|\.|:)?[[:digit:]]{2}[^[:digit:]]+[0-2][0-9](\-|\.|:)?[0-5][0-9](\-|\.|:)?[0-5][0-9]
#with capture groups:
#((1|2)[[:digit:]]{3})(\-|\.|:)?([[:digit:]]{2})(\-|\.|:)?([[:digit:]]{2})[^[:digit:]]+([0-2][0-9])(\-|\.|:)?([0-5][0-9])(\-|\.|:)?([0-5][0-9])
	fi
	#TODO: Check data before update??
	sqlite3 -batch $DB_FILE  "UPDATE $MAIN_TABLE SET RealDate='$realdate' where blake2='$blake2';"

        #FIX GPS too
        [[ $gpslatitude != '-' ]] && [[ $gpslongitude != '-' ]] && sqlite3 -batch $DB_FILE  "UPDATE $MAIN_TABLE SET GPSLatitude=$gpslatitude, GPSLongitude=$gpslongitude where blake2='$blake2';"
        return 0
    fi
}


difference (){
    # returns time difference in minutes
    #SHOULD BE Epoch
    local C=$(( $1 - $2 ))
    local D=$(echo $C | tr -d "-")
    echo $D
}
time_difference (){
    # returns time difference in minutes
    #SHOULD BE Epoch
    local C=$(( $1 - $2 ))
    local C=$(( $C / 60 ))
    local D=$(echo $C | tr -d "-")
    echo $D
}

convert_lalong (){
	# takes latitude or longitude with cardinal point and returns converted to positive/negative values
	# $1 -> LAt or long with cardinal point (NSWE)
	local lalong="$1"
	#convert if $1 has two array members (degrees and cardinal point)
	if [ ${lalong[#]} -gt 1 ] ;then
		if [[ ${lalong[1]} == S ]] ||  [[ ${lalong[1]} == W ]] ;then
			lalong=-${lalong[0]}
		else
			lalong=${lalong[0]}
		fi
	fi
}
reverse_geocoding (){
    # $! -> Latitude
    # $! -> Longitude
    # GET https://eu1.locationiq.com/v1/reverse.php?key=YOUR_PRIVATE_TOKEN&lat=LATITUDE&lon=LONGITUDE&format=json
    # fills global vars if possible (city,country,state,suburb,postcode)
    # reported error with openstreetmaps postcode
    # https://www.openstreetmap.org/note/2088580
    local latitude=$(convert_lalong "$1")
    local longitude=$(convert_lalong "$2")
    URL="https://eu1.locationiq.com/v1/reverse.php?key=$TOKEN&lat=$latitude&lon=$longitude&format=json"
    local out=$(sqlite3 -batch $GPS_FILE "select city,state,country,suburb,postcode,display from $GPS_TABLE where latitude like '${latitude}%' and longitude like '${longitude}%' limit 1;" | perl -pe 's/(?<!'"')'("'?!'"')/''/g")
    if [ -z "$out" ]; then
        # TODO: Duplicate every single quote before save in DB!
        # match single quotes (?<!')'(?!')
        local address=$(wget -q -O - "$URL" | perl -pe 's/(?<!'"')'("'?!'"')/''/g")
        #We must ensure that any subsequent call won't exceed the allowed usage
        #Normally 1 query per second (locationiq.com allows 2 per second)
        sleep 1

        city=$(echo $address | jq -r '.address.city')
        state=$(echo $address | jq -r '.address.state')
        country=$(echo $address | jq -r '.address.country')
        suburb=$(echo $address | jq -r '.address.suburb')
        postcode=$(echo $address | jq -r '.address.postcode')
        display=$(echo $address | jq -r '.display_name')

        [[ $city == null ]] && city=$(echo $address | jq -r '.address.village')
        [[ $city == null ]] && city=$(echo $address | jq -r '.address.town')
        sqlite3 -batch $GPS_FILE " insert or ignore into $GPS_TABLE values('$latitude','$longitude','$address','$city','$state','$country','$suburb','$postcode','$display');"
    #echo METAL
    else
        #select
        local tuple
        IFS='|' read -ra tuple <<< "$out"
        city="${tuple[0]}"
        state="${tuple[1]}"
        country="${tuple[2]}"
        suburb="${tuple[3]}"
        postcode="${tuple[4]}"
        display="${tuple[5]}"
    #echo CACHE
    fi
}

update_locations (){
    local line
    local tuple
    #local results=$(sqlite3 -batch $DB_FILE "select GPSLatitude,GPSLongitude,BLAKE2 from $MAIN_TABLE where GPSLatitude not like '-' ;")
    local results=$(sqlite3 -batch $DB_FILE "select GPSLatitude,GPSLongitude,BLAKE2 from $MAIN_TABLE where GPSLatitude not like '-' AND BLAKE2 not in (select blake2 from $LOCATIONS_TABLE);")

    #alternatively select only those which:
    # - have GPS metadata
    # - don't have an entry in locations
    #select GPSLatitude,GPSLongitude,BLAKE2 from fotos where GPSLatitude not like '-' AND BLAKE2 not IN (SELECT BLAKE2 FROM locations);
    while read line; do
    echo $line
        IFS='|' read -ra tuple <<< "$line"
        local latitude=${tuple[0]}
        local longitude=${tuple[1]}
        local blake2=${tuple[2]}
        [[ $latitude == "-" ]] && continue
        reverse_geocoding "$latitude" "$longitude"
        if exists_checksum $LOCATIONS_TABLE $blake2 ;then
            echo update
            echo "UPDATE $LOCATIONS_TABLE SET city='$city',state='$state',country='$country',suburb='$suburb',postcode='$postcode',display='$display' where blake2='$blake2';"
            sqlite3 -batch $DB_FILE <<EOF
UPDATE $LOCATIONS_TABLE SET city='$city',state='$state',country='$country',suburb='$suburb',postcode='$postcode',display='$display' where blake2='$blake2';
EOF
        else
            echo insert
            echo "insert or ignore into $LOCATIONS_TABLE values('$city','$state','$country','$suburb','$postcode','$display','$blake2');"
            sqlite3 -batch $DB_FILE <<EOF
insert or ignore into $LOCATIONS_TABLE values('$city','$state','$country','$suburb','$postcode','$display','$blake2');
EOF
        fi
    done <<< "$results"
# UPSERT since SQLITE 3.24
# INSERT INTO players (user_name, age)
#   VALUES('steven', 32)
#   ON CONFLICT(user_name)
#   DO UPDATE SET age=excluded.age;

# UPSERT older
# -- make sure it exists
# INSERT OR IGNORE INTO players (user_name, age) VALUES ('steven', 32);

# -- make sure it has the right data
# UPDATE players SET user_name='steven', age=32 WHERE user_name='steven';
}

longest_common_substring(){
    if ((${#1}>${#2})); then
       long=$1 short=$2
    else
       long=$2 short=$1
    fi

    lshort=${#short}
    score=0
    for ((i=0;i<lshort-score;++i)); do
        for ((l=score+1;l<=lshort-i;++l)); do
            sub=${short:i:l}
            [[ $long != *$sub* ]] && break
            subfound=$sub score=$l
        done
    done

    if ((score)); then
       echo "$subfound"
    fi
}

create_album (){
# select * from fotos Where CreateDate not like '-' order by CreateDate ASC;

# select f.CreateDate,l.* from fotos f,locations l Where CreateDate not like '-' AND f.BLAKE2=l.BLAKE2 order by CreateDate ASC;
    local offset=0
    local batch=200
    local results=""
    local current_date
    local old_date
    local diff=$(( $DIFFERENCE + 1 ))

    local blake2=""
    local city=""
    local country=""
    local display=""
    local postcode=""
    local state=""
    local longitude=""
    local latitude=""
    local suburb=""
    local old_blake2=""
    local old_city=""
    local old_country=""
    local old_display=""
    local old_postcode=""
    local old_state=""
    local old_suburb=""
    local old_longitude=""
    local old_latitude=""
    local new=""
    local lcs=""
    local album_name=""
    local current_albumid=""

    while
        results=$(sqlite3 -batch $DB_FILE "select f.CreateDate,l.city,l.state,l.country,l.suburb,l.postcode,l.blake2,f.GPSLatitude,f.GPSLongitude from fotos f,locations l Where CreateDate not like '-' AND f.BLAKE2=l.BLAKE2 order by CreateDate ASC limit $batch offset $offset;")
        offset=$(( $offset + $batch ))
        [ -n "$results" ]
    do

        while read line;do
            echo "$line"
            IFS='|' read -ra tuple <<< "$line"
            current_date=${tuple[0]}
            city=${tuple[1]}
            state=${tuple[2]}
            country=${tuple[3]}
            suburb=${tuple[4]}
            postcode=${tuple[5]}
            # display=${tuple[6]}
            blake2=${tuple[6]}
            latitude=${tuple[7]}
            longitude=${tuple[8]}

            new=0
            if [ -n "$old_date" ];then
                diff=$(time_difference "$old_date" "$current_date")
            fi
            if [ $diff -gt $DIFFERENCE ];then
                new=1
            fi
            if [[ $country == $old_country ]] && [[ $state == $old_state ]] ;then
                new=0
            fi
            if [ $new -eq 1 ] && [ -n "$old_postcode" ] && [ -n "$postcode" ] && [[ $postcode != "null" ]] && [[ $old_postcode != "null" ]] ;then
                if [[ "$postcode" == "$old_postcode" ]];then
                    new=0
                elif [ $(difference $postcode $old_postcode) -lt 5 ];then
                    new=0
                fi
            fi
            if [ -n "$latitude" ] && [ -n "$longitude" ] &&  [ -n "$old_latitude" ] && [ -n "$old_longitude" ] && \
               [[ "$latitude" != "-" ]] && [[ "$longitude" != "-" ]] && [[ "$old_latitude" != "-" ]] && [[ "$old_longitude" != "-" ]];then
                latitude=$(convert_lalong "$latitude")
                longitude=$(convert_lalong "$longitude")

                if [ $(distance $latitude $longitude $old_latitude $old_longitude ) -lt $DISTANCE ];then
                    new=0
                else
                    new=1
                fi
            fi

	    #Check if really new
	    #select latitude,longitude,ABS(longitude - -13.362500),ABS(latitude - 28.362500) from gps order by ABS(latitude - 28.362500) + ABS(longitude - -13.362500)  asc ;

            if [ $new -eq 1 ];then
                #clean album name (no nulls)
                local valid_names=()
                [[ $suburb != "null" ]]  && [[ $suburb != "-" ]]  && valid_names+=( "$suburb" )
                [[ $city != "null" ]]    && [[ $city != "-" ]]    && valid_names+=( "$city" )
                [[ $state != "null" ]]   && [[ $state != "-" ]]   && valid_names+=( "$state" )
                [[ $country != "null" ]] && [[ $country != "-" ]] && valid_names+=( "${country^^}" )

                album_name=$(date -d @$current_date +'%Y%m%d_' )$(join_by ", " "${valid_names[@]}")

		current_albumid=$(sqlite3 -batch $DB_FILE "select albumid from $ALBUM_TABLE where name='$album_name';")
		if [ -z $current_albumid ];then 
                    echo NEW album:  $album_name
                    sqlite3 -batch $DB_FILE " insert into $ALBUM_TABLE values('$album_name',null);"
                    current_albumid=$(sqlite3 -batch $DB_FILE " select albumid from $ALBUM_TABLE where name='$album_name';")
                fi
                #We keep the initial location names until a new album comes so we can decide if we change Album name in case e.g. of country border crossing, next near city, etc.
                old_city=$city
                old_country=$country
                old_display=$display
                old_postcode=$postcode
                old_state=$state
                old_suburb=$suburb
                lcs=""

                # if [ -n "$lcs" ];then
                # lcs=$(longest_common_substring "$suburb $city: $state, $country" "$lcs")
                # else
                #        lcs="$suburb $city: $state, $country"
                # fi
            fi
            sqlite3 -batch $DB_FILE  " UPDATE $MAIN_TABLE SET albumid='$current_albumid' where blake2='$blake2';"
            echo  "   - $(date -d @$current_date +'%Y%m%d_' ) $blake2"
            old_blake2=$blake2
            old_latitude=$latitude
            old_longitude=$longitude
            old_date=$current_date
        done <<< "$results"
    done
}

join_by (){ local IFS="$1"; shift; echo "$*"; }

distance (){
t=$(awk -v la1="$1"  -v lo1="$2" -v la2="$3"  -v lo2="$4" 'BEGIN{
    D2R=0.017453292519943295
    earth=6371

    dLa=(la2-la1)*D2R
    dLo=(lo2-lo1)*D2R
    la1r=(la1*D2R)
    la2r=(la2*D2R)

    a=sin(dLa/2)*sin(dLa/2)+sin(dLo/2)*sin(dLo/2)*cos(la1r)*cos(la2r)
    c=2*atan2(sqrt(a),sqrt(1-a))
    result=earth*c
    print result
}'

)
#echo $t
#echo truncated:
LC_NUMERIC="en_US.UTF-8" printf %.0f "$t"
}

smash(){
    recreate_album_table
    sqlite3 -batch $DB_FILE  " UPDATE $MAIN_TABLE SET albumid='';"
}

usage(){
    cat <<EOF

albumathor
----------
Creates stupid albums according to predefined rules.

It Uses GPS coordinates from EXIF metadata (if available) to better determine which photos can go together. It needs an API token from a third-party reverse geocoding service (locationiq.com) to get human-readable locations.

Usage
-----

Create initial DB:
albumathor.sh <PATH>

Generate locations:
albumathor -gps

Create albums (only in DB):
albumathor -thor

Create albums (symlink):
albumathor -thor -s <destination path>

Create albums (hardlink):
albumathor -thor -h <destination path>

Create albums (copy):
albumathor -thor -c <destination path>

Delete all album associations (in DB only):
albumathor -smash

EOF
}

# Execution Starts here
# ---------------------

DB_FILE=$HOME/.config/albumathor/fotos_archive.db
GPS_FILE=$HOME/.config/albumathor/gps-cache.db
CONFIG_FILE=$HOME/.config/albumathor/albumathor.conf
FAST=1
MAIN_TABLE=fotos
ALBUM_TABLE=albums
LOCATIONS_TABLE=locations
GPS_TABLE=gps
FORMAT=$HOME/.config/albumathor/format.fmt
DIFFERENCE=300
DISTANCE=30
MINSIZE=50k
DESTINATION=/tmp/albumathor

[ -f $HOME/.config/albumathor/albumathor.conf ] && source $HOME/.config/albumathor/albumathor.conf
case $1 in
    -gps)
        update_locations
        exit
        ;;
    -thor)
        #DESTINATION="$2"
        #{ [ -d $DESTINATION ] && [ -r "$DESTINATION" ] && [ -w "$DESTINATION" ] && [ -x "$DESTINATION" ] ;} || mkdir -p "$DESTINATION" || exit
        create_album
        exit
        ;;
    -smash)
        smash
        exit
        ;;
#     *)
#         usage
#         exit 1
#         ;;
esac

[ -f $DB_FILE ]  || create_database
[ -f $GPS_FILE ] || create_gps_cache

path=$(readlink -f "$1")
#TODO:
# check file/dir existence
# check binaries existence
# check config

#Mixed Collections messes up album creation
# If -thor files from multiple collections from different people it can happen that different persons are in different locations at the same time.
# The main principle to guess Album names is proximity of location and time so this scenario will originate alternating albums with one or two files and roughly the same date just changing the location:
# - 2020-01-05 Boston
#    - IMG000354.jpg
# - 2020-01-05 California
#    - DSC00044456.jpg
#    - DSC00044457.jpg
# - 2020-01-05 Boston
#    - IMG000355.jpg
#    - IMG000356.jpg
# - 2020-01-05 California
#    - DSC00044458.jpg
# -... and so on
#
# If the album name is exactly the same it would be ok but oftentimes location changes to the adjacent neighborhood or city and what should be e.g. a daytrip album ends up being a complete mess
# The solution would be to maintain an albums table with:
#  - Begin Date
#  - End Date
#  - Location(s?)
#  - Last-location?
#  - Name
#  - ID to serve as foreign key in the main table
# And try to add each file to an existing album before creating a new one

#REAL date
# There seems to be no definitive and reliable EXIF field for Date. I even encounter some wrong dates saved in EXIF metadata, leaving the filename as the only alternative to obtain the real date of the file.
#
# We need to:
#  - add a new column in DB for REAL date
#  - find out the most probable real date comparing different EXIF fields
#  - program a method to extract date from filename probing regexes with different date formats
#  - stablish a level of confidence and resort to filename date guessing only if necessary
#  - Fix the original file Metadata???

#NO GPS data
# If the file doesn't have gps data, that leaves us with only the date proximity to try and create the albums.
# One way around it is downloading GPS data from google (if available) and use it to fill the EXIF metadata
# another possibility is to have a list of festivities or meaningful dates which could give a name to an album (Christmas, New Years Eve, Thanks Giving, 4th July, St Patricks) or even custom ones through config file.
#
#Known locations
# Give the user the possibility to mark some known locations to avoid creating many albums with the same uninteressant names so instead of e.g. 'Marienplatz 10, Munich, Bavaria, Germany' it would say 'Home - Munich' or whatever the user defines. We could even group them together or make sub-albums under that folder

if [ -d "$path" ]; then
    while IFS= read -r -d '' file; do
        echo "checking $file from $path"
        bytesize=$(wc -c <"$file")
        if [ $FAST -eq 1 ]; then
            if exists_file "$file" $bytesize ; then continue; fi
        fi
        sum=$(b2sum "$file" | cut -f 1 -d " ")
        if exists_checksum fotos $sum ;then continue ;fi
        #tuple=$(exiftool -f -d "%Y-%m-%d %H:%M:%S" -c '%.6f' -p $FORMAT "$file")
        tuple=$(exiftool -f -d "%s" -c '%.6f' -p $FORMAT "$file")
        tuple="\"$file\",$tuple"
        insert "$tuple" $bytesize $sum
        echo $?
    done < <(find "$path" \( -iname "*.jpg" -or -iname "*.jpeg" -or -iname "*.png" -or -iname "*.heic" \) -size +$MINSIZE -type f  -print0)
    #find "$path" \( -iname "*.jpg" -or -iname "*.jpeg" -or -iname "*.png" -or -iname "*.tif" -or -iname "*.bmp" -or -iname "*.gif" -or -iname "*.xpm" -or -iname "*.nef" -or -iname "*.cr2" -or -iname "*.arw" \) -size +20k
    #find "$path" \( -iname "*.jpg" -or -iname "*.jpeg" -or -iname "*.png" \) -size +20k
elif [ -f "$path" ];then
    file="$path"
    echo "checking $file"
    bytesize=$(wc -c <"$file")
    if [ $FAST -eq 1 ]; then
        if exists_file "$file" $bytesize ; then continue; fi
    fi
    sum=$(b2sum "$file" | cut -f 1 -d " ")
    if exists_checksum fotos $sum ;then continue ;fi

    tuple=$(exiftool -f -d "%s" -c '%.6f' -p $FORMAT "$file")
    tuple="\"$file\",$tuple"
    insert "$tuple" $bytesize "$sum"
    echo $?
else
    usage
    exit 1
fi

