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
    'BLAKE2'    TEXT NOT NULL PRIMARY KEY
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
create_album_table(){
    sqlite3 $DB_FILE <<EOF

BEGIN TRANSACTION;
CREATE TABLE IF NOT EXISTS '$ALBUM_TABLE' (
    'NAME' TEXT NOT NULL,
    'DATE1' TEXT NOT NULL,
    'DATE2' TEXT,
    'BLAKE2' TEXT NOT NULL PRIMARY KEY,
    FOREIGN KEY (BLAKE2) REFERENCES $MAIN_TABLE (BLAKE2)
            ON DELETE CASCADE ON UPDATE NO ACTION
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
    local sum="$3"

    if exists_checksum fotos $sum ;then
        echo $?
        echo exists
        return 302
    else
        echo "inserting $tuple,$bytesize,$sum"
        sqlite3 -batch $DB_FILE <<EOF
pragma busy_timeout=2000;
insert into $MAIN_TABLE values($tuple,$bytesize,'$sum');
EOF
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

dmg2dd_lat(){
    local latitude=( $1 )
    { [[ ${latitude[1]} == S ]] && latitude=-${latitude[0]} ;} || latitude=${latitude[0]}
    echo $latitude
}

dmg2dd_long(){
    local longitude=( $1 )
    { [[ ${longitude[1]} == W ]] && longitude=-${longitude[0]} ;} || longitude=${longitude[0]}
    echo $longitude
}

reverse_geocoding (){
    # $! -> Latitude
    # $! -> Longitude
    # GET https://eu1.locationiq.com/v1/reverse.php?key=YOUR_PRIVATE_TOKEN&lat=LATITUDE&lon=LONGITUDE&format=json
    # fills global vars if possible (city,country,state,suburb,postcode)
    local latitude=$(dmg2dd_lat "$1")
    local longitude=$(dmg2dd_long "$2")
    URL="https://eu1.locationiq.com/v1/reverse.php?key=$TOKEN&lat=$latitude&lon=$longitude&format=json"
    local out=$(sqlite3 -batch $GPS_FILE "select city,state,country,suburb,postcode from $GPS_TABLE where latitude='$latitude' and longitude='$longitude';")|perl -pe 's/(?<!'"')'("'?!'"')/''/g"
    if [ -z "$out" ]; then
        # TODO: Duplicate every single quote before save in DB!
        # match single quotes (?<!')'(?!')
        local address=$(wget -q -O - "$URL" | perl -pe 's/(?<!'"')'("'?!'"')/''/g")
        #We must ensure that any subsequent call won't exceed the allowed usage
        #Normally 1 query per second (locationiq.com allows 2 per second)
        sleep 1
        
        country=$(echo $address | jq -r '.address.country')
        state=$(echo $address | jq -r '.address.state')
        city=$(echo $address | jq -r '.address.city')
        suburb=$(echo $address | jq -r '.address.suburb')
        postcode=$(echo $address | jq -r '.address.postcode')
    display=$(echo $address | jq -r '.display_name')
        
        [[ $city == null ]] && city=$(echo $address | jq -r '.address.village')
        [[ $city == null ]] && city=$(echo $address | jq -r '.address.town')
        sqlite3 -batch $GPS_FILE "pragma busy_timeout=2000; insert or ignore into $GPS_TABLE values('$latitude','$longitude','$address','$city','$state','$country','$suburb','$postcode','$display');"
    else
        #select
        local tuple
        IFS='|' read -ra tuple <<< "$out"
        state="${tuple[0]}"
        city="${tuple[1]}"
        country="${tuple[2]}"
        suburb="${tuple[3]}"
        postcode="${tuple[4]}"
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
            echo "UPDATE $LOCATIONS_TABLE SET city='$city',state='$state',country='$country',suburb='$suburb',postcode='$postcode' where blake2='$blake2';"
            sqlite3 -batch $DB_FILE <<EOF
pragma busy_timeout=20000;
UPDATE $LOCATIONS_TABLE SET city='$city',state='$state',country='$country',suburb='$suburb',postcode='$postcode' where blake2='$blake2';
EOF
        else
            echo insert
            echo "insert or ignore into $LOCATIONS_TABLE values('$city','$state','$country','$suburb','$postcode','$blake2');"
            sqlite3 -batch $DB_FILE <<EOF
pragma busy_timeout=20000;
insert or ignore into $LOCATIONS_TABLE values('$city','$state','$country','$suburb','$postcode','$blake2');
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
            if [[ $postcode != "null" ]] && [[ $old_postcode != "null" ]] &&  [ $(difference $postcode $old_postcode) -lt 5 ];then
                new=0
            fi
            if [ -n "$latitude" ] && [ -n "$longitude ] &&  [ -n "$old_latitude" ] && [ -n "$old_longitude ] && \
               [[ "$latitude" != "-" ]] && [[ "$longitude" != "-" ]] && [[ "$old_latitude" != "-" ]] && [[ "$old_longitude" != "-" ]];then
                latitude=$(dmg2dd_lat "$latitude")
                longitude=$(dmg2dd_long "$longitude")

                if [ $(distance $latitude $longitude $old_latitude $old_longitude ) -lt 10 ];then
                    new=0
                fi
            fi
            if [ $new -eq 1 ];then
                echo NEW album. Name: $(date -d @$current_date +'%Y%m%d_' ) $suburb $city: $state, $country
                old_blake2=$blake2
                old_city=$city
                old_country=$country
                old_display=$display
                old_postcode=$postcode
                old_state=$state
                old_suburb=$suburb
                lcs=""
            else
                # if [ -n "$lcs" ];then
                # lcs=$(longest_common_substring "$suburb $city: $state, $country" "$lcs")
                # else
                #        lcs="$suburb $city: $state, $country"
                # fi
                echo  "   - $(date -d @$current_date +'%Y%m%d_' ) $suburb $city: $state, $country $lcs"
            fi
            old_latitude=$latitude
            old_longitude=$longitude
            old_date=$current_date
        done <<< "$results"
    done
}

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
printf %.0f "$t"
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
albumathor -thor -s

Create albums (hardlink):
albumathor -thor -h

Create albums (copy):
albumathor -thor -c

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

[ -f $HOME/.config/albumathor/albumathor.conf ] && source $HOME/.config/albumathor/albumathor.conf
case $1 in
    -gps)
        update_locations
        exit
        ;;
    -thor)
        create_album
        exit
        ;;
    *)
        usage
        exit 1
        ;;
esac

[ -f $DB_FILE ]  || create_database
[ -f $GPS_FILE ] || create_gps_cache

path=$(readlink -f "$1")
#TODO:
# check file/dir existence
# check binaries existence
# check config

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
        insert "$tuple" $bytesize "$sum"
        echo $?
    done < <(find "$path" -type f  -print0)
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


