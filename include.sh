#!/bin/bash
# Auxiliary functions moved out of main file to declutter


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
    if [ ${#lalong[@]} -gt 1 ] ;then
        if [[ ${lalong[1]} == S ]] ||  [[ ${lalong[1]} == W ]] ;then
            lalong=-${lalong[0]}
        else
            lalong=${lalong[0]}
        fi
    fi
    echo $lalong
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

join_by (){ local IFS="$1"; shift; echo "$*"; }

# distance latitude1 longitude1 latitude2 longitude2
# measures the distance in km between two coordinates
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

