#!/bin/bash
#title          :build-dkms-dir.sh
#description    :Script collects sources from web and generates a DKMS package directory.
#author         :XDN (https://github.com/andrew-xdn)
#date           :21.12.2017
#version        :0.2    
#usage          :bash build-dkms-dir.sh [--pack | -p] [--checksum | -s] [--clean | -c] [--help | -h] [--version | -V]
#notes          :Ensure you have "pwd", "grep", "curl", "tar", "gzip", "tr", "rm", "mkdir", "md5sum" utilities before running
#                    this script.
#bash_version   :4.3.48(1)-r
#==============================================================================

#==SCRIPT SETTINGS==
# Script version
VERSION="0.2"
# DKMS configuration file name
DKMS_CONFIGURATION="dkms.conf"
# DKMS makefile name
DKMS_MAKEFILE="Makefile"
# Package sources file name (Unix text file, source per line)
PACKAGE_SOURCES="SOURCES"
# Package include file name (Unix text file, file per line)
INCLUDE_FILE="INCLUDE"
# Prefix for website URL that doesn't contain kernel sources root
NKSR_PREFIX="!"
# A list visual mark for websites that don't contain kernel sources root
NKSR_VISUAL_MARK="(NKSR)"
# A prefix for web files to include into package
INCLUDED_WEB_FILE_PREFIX=":"
# A list visual mark for web files to include into package (at the website root)
INCLUDED_FILE_WEB_MARK="(Web)"
# A list visual mark for web files needed to include into package (by URL)
INCLUDED_FILE_WEB_URL_MARK="(URL)"
# Web client advanced configuration file (one line additional command line arguments)
WEB_ADVANCED_FILE="WEB_CONFIG"
# Output checksums file name
CHEKSUMS_FILE="MD5SUMS"
#==================

#==INCLUDED FILE TYPE==
# Local file
INCLUDED_FILE_LOCAL=0
# Web file (at the website root)
INCLUDED_FILE_WEB=1
# Web file (by URL)
INCLUDED_FILE_WEB_URL=2
#==================

# Extracts a parameter's ($1) value from the DKMS configuration, trims double quotes in the value
dkms_extract()
{
    # This function uses grep regexp in POSIX mode:
    #   <parameter>=<value>
    #        <value> has to contain at least one literal, digit, symbol: "-", "_", ".".
    #        Hint: avoid regexp special character in <parameter>!
    #   Returns: <value>.
    grep -Po "^$1=\K([[:alnum:]]|[-_.])+$" $DKMS_CONFIGURATION | tr -d \"
}

# Extracts an array's ($1) values from the DKMS configuration, trims double quotes in the values
dkms_extract_array()
{
    # This function uses grep regexp in POSIX mode:
    #   <array>[<index>]=<value>
    #       <index> has to contain at least one digit;
    #       <value> has to contain ay least one literal, digit, symbol: "-", "_", "/", "$", """.
    #       Hint: avoid regexp special character in <array>!
    #   Returns: \n separeted list of <value>s. Safe to set to a bash array.
    grep -Po "^$1\[[[:digit:]]+]=\K([[:alnum:]]|[-_/$\"])+$" $DKMS_CONFIGURATION | tr -d \"
}

# Extracts a content from a string ($2) with a prefix ($1)
# Returns:
#   0 - successfully extracted,
#   <>0 - a string dosn't have a prefix.
prefix_extract()
{
    # This function uses grep regexp in POSIX mode:
    #   [<prefix>]<content>
    #       <prefix> has to be $1 argument;
    #       <content> has to contain ay least one non-space symbol.
    #       Hint: avoid regexp special character in <prefix>!
    #   Returns: <content>.
    #   TODO: Make <content> regexp part more stricted.
    echo "$2" | grep -Po "^$1\K[^ ]+$"
    return $?
}

# Asks user to select a website for web resources with UI text offset ($1). Sets results in global variables.
#   RESOURCES_WEBSITE - a website to use when downloading web resouces.
#   RESOURCES_WEBSITE_NKSR_FLAG - a mark that website doesn't contains kernel sources root.
#   WARNING: RESOURCES_WEBSITES, RESOURCES_WEBSITE_NKSR_FLAGS have to be initialised before first function call.
#   Hint: After first website selection function does nothing. 
select_website()
{
    # Checking if the user already selected a sources website
    if [[ -z $RESOURCES_WEBSITE ]]
    then
        # If the file with sources websitea was empty
        if [[ ${#RESOURCES_WEBSITES[@]} == 0 ]]
        then
            echo "No website for the resource avalible!"
            exit 50
        fi
        echo -en "$1└ Resource availible at"
        # If user actually doesn't have a choice
        if [[ ${#RESOURCES_WEBSITES[@]} == 1 ]]
        then
            echo -n " ${RESOURCES_WEBSITES[0]}"
            # Adding NKSR visual mark if needed
            if [[ "${RESOURCES_WEBSITE_NKSR_FLAGS[$i2]}" == false ]]
            then
                echo
            else
                echo " $NKSR_VISUAL_MARK"
            fi
            # Selecting the only websity availible
            user_selection=0
        else
            echo ":"
            # Printing availible website to the user
            for i2 in "${!RESOURCES_WEBSITES[@]}"
            do
                # Incrementing every index to make dialog human readable
                echo -ne "$1\t $(($i2+1))) ${RESOURCES_WEBSITES[$i2]}"
                # Adding NKSR visual mark if needed
                if [[ "${RESOURCES_WEBSITE_NKSR_FLAGS[$i2]}" == false ]]
                then
                    echo
                else
                    echo " $NKSR_VISUAL_MARK"
                fi
            done
            # We can't use "read -p" because of tabs in $1
            echo -ne "$1Select website: "
            # Asking for a user input
            read user_selection
            # No input check
            if [[ -z "$user_selection" ]]
            then
                echo "No input entered!"
                exit 51
            fi
            # Only digits allowed
            if [[ -n ${user_selection//[0-9]/} ]]
            then
                echo "User input has to be a positive integer!"
                exit 52
            fi
            # Low limit check
            if [[ $user_selection == 0 ]]
            then
                echo "User input can't be less than 1!"
                exit 52
            fi
            # Hight limit check
            if [[ $user_selection > ${#RESOURCES_WEBSITES[@]} ]]
            then
                echo "User input can't be more than ${#RESOURCES_WEBSITES[@]}!"
                exit 52
            fi
            # We've incremented every index for user. Now calculating actual index.
            user_selection=$(($user_selection-1))
        fi
        # Extracting a reasources website URL, removing / at the end if exists
        RESOURCES_WEBSITE=${RESOURCES_WEBSITES[$user_selection]%/}
        # Extracting a resources website NKSR flags
        RESOURCES_WEBSITE_NKSR_FLAG=${RESOURCES_WEBSITE_NKSR_FLAGS[$user_selection]}
    fi
}

# Downloads a web resource ($1)
# WARNING: WEB_ADVANCED should be initialized before first call
download_file()
{
    # Downloading a web resource using curl silently and saving it to the file with a remote file name (-O) 
    # WARNING: Don't quotate WEB_ADVANCED
    curl $WEB_ADVANCED -O "$1" > /dev/null 2>&1
}

echo "-- DKMS directory builder v$VERSION --"

# Pack directory into tarball flag (false by default)
PACK_DIRECTORY=false
# Calcualte tarball's checksum flag (false by default)
CALCULATE_CHECKSUM=false
# Clean all previous output flag (false by default)
CLEAN_OUTPUT=false
# Reading command line arguments
for argument in "$@"
do
    case "$argument" in
    # User requested to pack the output directory to a tarball
    "--pack" | "-p" )
        PACK_DIRECTORY=true
    ;;
    # User requested to calculate tarball's checksuma
    "--checksum" | "-s" )
        CALCULATE_CHECKSUM=true
    ;;
    # User requested to clean all previous script output
    "--clean" | "-c" )
        CLEAN_OUTPUT=true
    ;;
    # User requested help
    "--help" | "-h" )
        echo "Usage: build-dkms-dir.sh [--pack | -p] [--clean | -c] [--help | -h] [--version | -V]"
        echo -e "\t[--pack | -p] - pack an output directory to a gzipped tarball;"
        echo -e "\t[--checksum | -s] - calculate tarball's checksum;"
        echo -e "\t[--clean | -c] - clean all previous script output, if exists (DKMS package directory and DKMS package tarball);"
        echo -e "\t[--help | -h] - print usage information (this text);"
        echo -e "\t[--version | -V] - print script version."
        # Normal exit
        exit 0
    ;;
    # User requested application version
    "--version" | "-V" )
        # Normal exit
        exit 0
    ;;
    # Unknown argument
    * )
        echo
        echo "Unknown argument \"$argument\"!"
        exit 1
    esac
done
echo
# We can't calculate tarball's checksum without a tarball
if [[ "$CALCULATE_CHECKSUM" == true && "$PACK_DIRECTORY" == false ]]
then
    echo 'Checksum option is avalible only with the option [--pack | -p].'
    exit 2
fi

#==ENVIRONMENT CHECK (do we actually need that?)==
pwd > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No pwd utility in the environment!"
    exit 3
fi
grep -V > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No grep utility in the environment!"
    exit 3
fi
curl -V > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No curl utility in the environment!"
    exit 3
fi
tar --version > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No tar utility in the environment!"
    exit 3
fi
gzip -V > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No gzip utility in the environment!"
    exit 3
fi
tr --version > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No tr utility in the environment!"
    exit 3
fi
rm --version > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No rm utility in the environment!"
    exit 3
fi
mkdir --version > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No mkdir utility in the environment!"
    exit 3
fi
md5sum --version > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "No md5sum utility in the environment!"
    exit 3
fi
#==================

# Helps user to determine the project directory
echo "Working directory: \"$(pwd)\""

# Advanced web client configuration (additional command line arguments to pass for a web client) (empty at this moment)
WEB_ADVANCED=""
if [[ -f "$WEB_ADVANCED_FILE" ]]
then
    # Loading from file
    WEB_ADVANCED=$(cat "$WEB_ADVANCED_FILE" | tr '\n\r' ' ')
    echo "Advanced web client configuration loaded."
fi
# Checks if the extrernal resources file exists
if [[ -f "$PACKAGE_SOURCES" ]]
then
    # Reading sources websites into an array
    RESOURCES_WEBSITES=($(cat "$PACKAGE_SOURCES"))
else
    # Just keeps empty
    RESOURCES_WEBSITES=()
fi
# Keeps NKSR (not kernel source root) for each website
RESOURCES_WEBSITE_NKSR_FLAGS=()
# Looking throught every website URL
for i in "${!RESOURCES_WEBSITES[@]}"
do 
    # Trying to separate URL from a prefix
    clean_content=$(prefix_extract "$NKSR_PREFIX" "${RESOURCES_WEBSITES[$i]}")
    if [[ $? == 1 ]]
    then
        # URL doesn't have a prefix 
        RESOURCES_WEBSITE_NKSR_FLAGS[$i]=false
    else
        # It has!
        RESOURCES_WEBSITE_NKSR_FLAGS[$i]=true
        # Saving clean URL without a prefix to the array
        RESOURCES_WEBSITES[$i]=$clean_content
    fi
done

# Resources wibsite selected by user (empty at this moment)
RESOURCES_WEBSITE=""
# Resources wibsite NKSR flag (flase at this moment)
RESOURCES_WEBSITE_NKSR_FLAG=false

echo "Main DKMS package files:"
# Keeps main file names downloaded from a website (to delete at the cleening phase) (empty at this moment)
BASE_FILES_WEB=()
# Looking throught a static main files set
for file in "$DKMS_CONFIGURATION" "$DKMS_MAKEFILE"
do
    echo -e "\t$file"
    # Checks if a main DKMS package file exists
    if [[ ! -f "$file" ]]
    then
        # Not exists, looking for a web version
        # Should ask the user to select website for web resources. Does nothing if already selected.
        select_website "\t"
        # Assembling file URL
        # WARNING: If user selected a kernel source root website, then file will be downloaded from the root directory
        file_url="$RESOURCES_WEBSITE/$file"
        echo -en "\t└ Downloading... "
        # Downloading a main file from web
        download_file "$file_url"
        if [[ $? != 0 ]]
        then
            echo "failed."
            exit 4
        fi
        echo "done."
        # Adding file to the array to delete at cleaning phase
        BASE_FILES_WEB+=( "$file" )
    else
        # Local copy found
        echo -e "\t└ Using local file."
    fi
done

# Checks if the included files list file presented 
if [[ -f "$INCLUDE_FILE" ]]
then
    # Reading included files into an array
    INCLUDED_FILES=($(cat "$INCLUDE_FILE"))
else
    # Keeps empty
    INCLUDED_FILES=()
fi

# Extracting package name
PACKAGE_NAME=$(dkms_extract "PACKAGE_NAME")
if [[ -z "$PACKAGE_NAME" ]]
then
    echo "Package name isn't set!"
    exit 5
fi
# Extracting package version (we need that to assemble a DKMS package directory name)
PACKAGE_VERSION=$(dkms_extract "PACKAGE_VERSION")
if [[ -z "$PACKAGE_VERSION" ]]
then
    echo "Package version isn't set!"
    exit 6
fi
# Extracting modules' names
BUILT_MODULE_NAMES="$(dkms_extract_array 'BUILT_MODULE_NAME')"
if [[ ${#BUILT_MODULE_NAMES[@]} == 0 ]]
then
    echo "You have to add at least one module!"
    exit 7
fi
# Looking throught the modules' names
for i in "${!BUILT_MODULE_NAMES[@]}"
do 
    # A module name may contain $PACKAGE_NAME keyword we should replace by actual package name
    if [[ "${BUILT_MODULE_NAMES[$i]}" == "\$PACKAGE_NAME" ]]
    then
        BUILT_MODULE_NAMES[$i]=$PACKAGE_NAME
    fi
done
# Extracting modules' locations in the target operating system
DEST_MODULE_LOCATIONS="$(dkms_extract_array 'DEST_MODULE_LOCATION')"

echo "DKMS package summary:"
echo -e "\tPackage name: $PACKAGE_NAME"
echo -e "\tPackage version: $PACKAGE_VERSION"
# Array contains sources from Web we should delete in the end (empty at this moment)
SOURCES_WEB_FILES=()
# Each location has to be assaigned for a module
if [[ ${#BUILT_MODULE_NAMES[@]} != ${#DEST_MODULE_LOCATIONS[@]} ]]
then
    echo "Number of module locations has to be equal to number of modules!"
    exit 8
fi
echo -e "Modules:"
# Looking throught modules' names
for i in "${!BUILT_MODULE_NAMES[@]}"
do 
    # A module source file name
    module_source="${BUILT_MODULE_NAMES[$i]}.c"
    echo -e "\t$module_source --> ${DEST_MODULE_LOCATIONS[$i]}"
    # Looking for a local module copy
    if [[ -f "$module_source" ]]
    then
        echo -e "\t\t└ Using local file."
    else
        # We don't have a local copy. Should ask the user to select website for web resources. Does nothing if already selected.
        select_website "\t"
        # Checks if selected website has kernel source root
        if [[ "$RESOURCES_WEBSITE_NKSR_FLAG" == false ]]
        then
            # It does!
            # Extracting a module location, removing ending / if found
            source_directory="${DEST_MODULE_LOCATIONS[$i]%/}"
            # To assemble a source code URL we have to concat a sources website URL and a module location without "/kernel" prefix
            #   directory
            source_file_url="$RESOURCES_WEBSITE${source_directory/\/kernel}/$module_source"
        else
            # It doesn't...
            # Then the module source file just in the website's root directory
            source_file_url="$RESOURCES_WEBSITE/$module_source"
        fi
        echo -en "\t└ Downloading... "
        # Downloading
        download_file "$source_file_url"
        if [[ $? != 0 ]]
        then
            echo "failed."
            exit 9
        fi
        echo "done."
        # Saving module source file name to delete at the cleaning phase
        SOURCES_WEB_FILES+=( "$module_source" )
    fi
done

# Contains included file names we downloaded from Web to delete at the cleaning phase (empty at this moment)
INCLUDED_WEB_FILES=()
# If user requested additional files to include into DKMS package
if [[ ${#INCLUDED_FILES[@]} > 0 ]]
then
    echo "This files will be included with DKMS module:"
    # Checking every file name
    for i in "${!INCLUDED_FILES[@]}"
    do 
        # Current included file type (local at this moment)
        file_type=$INCLUDED_FILE_LOCAL
        # Trying to separate file name from a a prefix
        clean_content=$(prefix_extract "$INCLUDED_WEB_FILE_PREFIX" "${INCLUDED_FILES[$i]}")
        if [[ $? == 0 ]]
        then
            # Checking if it's URL
            # Trying to separate file name from URL using POSIX regexp:
            #   <protocol>://<domain_rest>.<domain_1><path>/<file_name>, where:
            #       <protocol> has to contain at least one letter or number;
            #       <domain_rest> has to contain least one letter, number, symbol: ".";
            #       <domain_1> has to contain between 3 and 6 letters;
            #       <path> may contain letters, numbers, symbols: ".", "/", "?", "=", "_", "-";
            #       <file_name> has to contain at least one letter, number, symbols: "-", "_", ".".
            # TODO: Need more strict regexp for the file name?
            clean_file=$(echo "$clean_content" | \
                grep -Po "^[[:alnum:]]+://([[:alnum:]]|[.])+.[[:alnum:]]{3,6}/([[:alnum:]]|[./?=_-])*/\K([[:alnum:]]|[-_.])+$")
            if [[ $? == 0 ]]
            then
                # It is URL!
                # Changing included file type
                file_type=$INCLUDED_FILE_WEB_URL
                # Saving actual file URL
                file_url=$clean_content
                # Saving actual file name to the array
                INCLUDED_FILES[$i]=$clean_file
            else
                # It's not!
                # Saving relative file URL (or just a file name)
                file_url=$clean_content
                # Changing included file type
                file_type=$INCLUDED_FILE_WEB
                # Checking if it's a relative web path
                # Trying to separate file name from URL using POSIX regexp:
                #   */<file_name>, where:
                #       <file_name> has to contain at least one letter, number, symbols: "-", "_", ".".
                # TODO: Need more strict regexp for the file name?
                clean_file=$(echo "$clean_content" | grep -Po "/\K([[:alnum:]]|[-_.])+$")
                if [[ $? == 0 ]]
                then
                    # Saving actual file name (not a relative path) to the array
                    INCLUDED_FILES[$i]=$clean_file
                else
                    # Saving actual file name (without prefix) to the array
                    INCLUDED_FILES[$i]=$clean_content
                fi
            fi 
            # Adding the included web file name to the array to delete it at the cleaning phase
            INCLUDED_WEB_FILES+=( ${INCLUDED_FILES[$i]} )
        fi
        # Other action depends on included file type
        case "$file_type" in
        # Local file
        "$INCLUDED_FILE_LOCAL" )
            echo -e "\t${INCLUDED_FILES[$i]}"
            # Checking if the file exists
            if [[ ! -f "${INCLUDED_FILES[$i]}" ]]
            then
                echo -e "\t\t└ Not found!."
                exit 10
            fi
            echo -e "\t└ Using local file."
        ;;
        # Web file
        "$INCLUDED_FILE_WEB" | "$INCLUDED_FILE_WEB_URL" )
            echo -en "\t${INCLUDED_FILES[$i]} "
            # Printing a mark that depends on the included file type
            if [[ "$file_type" == "$INCLUDED_FILE_WEB" ]]
            then
                echo "$INCLUDED_FILE_WEB_MARK"
            else
                echo "$INCLUDED_FILE_URL_MARK"
            fi
            # Should ask the user to select website for web resources. Does nothing if already selected.
            select_website "\t"
            if [[ "$file_type" == "$INCLUDED_FILE_WEB" ]]
            then
                # We can get the actual URL for a Web included file only now
                # Works both for just a file or a relative path
                # WARNING: If user selected a kernel source root website, then web included file should be in the root
                file_url="$RESOURCES_WEBSITE/$file_url"
            fi
            echo -en "\t└ Downloading... "
            # Downloading a web included file (ovewrite, if)
            download_file "$file_url"
            if [[ $? != 0 ]]
            then
                echo "failed."
                exit 11
            fi
            echo "done."
            esac   
    done
fi

# Assembling a DKMS package directory name
OUTPUT_DIRECTORY_ROOT="$PACKAGE_NAME-$PACKAGE_VERSION"
# If directory already exists
if [[ -d "$OUTPUT_DIRECTORY_ROOT" ]]
then
    # It's okay, user requested to clean this for him...
    if [[ "$CLEAN_OUTPUT" == true ]]
    then
        echo -n "Removing output directory... "
        rm -r $OUTPUT_DIRECTORY_ROOT > /dev/null 2>&1
        if [[ $? != 0 ]]
        then
            echo "failed."
            exit 12
        fi
        echo "done."
    else
        # User have to delete the directory manually or enter the --clean argument
        echo "Output directory exists. Please, remove it manually to generate a new one."
        exit 13
    fi
fi
echo -n "Generating directory... "
# Creating a new directory for the DKMS package
mkdir "$OUTPUT_DIRECTORY_ROOT" > /dev/null 2>&1
if [[ $? != 0 ]]
then
    echo "failed."
    exit 14
fi
echo "done."

# An array contains file to copy (DKMS configuration file and DKMS makefile by default)
COPY_SOURCES=("$DKMS_CONFIGURATION" "$DKMS_MAKEFILE")
# Source file for every module have to be added (by adding ".c" extension to a module name)
for module in "${BUILT_MODULE_NAMES[@]}"
do 
    COPY_SOURCES+=( "$module.c" )
done
# Adding files from the included files list
COPY_SOURCES+=( "${INCLUDED_FILES[@]}" )
echo -n "Copying files... "
# Copying all files to the output DKMS package directory
for file in "${COPY_SOURCES[@]}"
do 
    cp "$file" "$OUTPUT_DIRECTORY_ROOT" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        echo "failed."
        exit 15
    fi
done
echo "done."

# Assemblying a name of the output tarball
OUTPUT_TARBALL="$PACKAGE_NAME-$PACKAGE_VERSION.tar.gz"
# If the tarball file already exists
if [[ -f "$OUTPUT_TARBALL" ]]
then
    # It's okay if user requested to delete it
    # Hint: Even if user doesn't request to pack new directory the old tarball will be deleted to avoid mistakes!
    if [[ "$CLEAN_OUTPUT" == true ]]
    then
        echo -n "Removing output tarball... "
        rm $OUTPUT_TARBALL > /dev/null 2>&1
        if [ $? != 0 ]
        then
            echo "failed."
            exit 16
        fi
        echo "done."
    else
        # User have to delete the tarball manually or enter the --clean argument
        echo "Output tarball exists. Please, remove it manually to generate a new one."
        exit 17
    fi
fi
# Creating new tarball only if the user requests to pack the directory
if [[ "$PACK_DIRECTORY" == true ]]
then
    echo -n "Preparing tarball... "
    # Packing the output directory into gzipped tarball
    tar -zcvf "$OUTPUT_TARBALL" "$OUTPUT_DIRECTORY_ROOT" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        echo "failed."
        exit 18
    fi
    echo "done."
fi

# If the checksums file already exists
if [[ -f "$CHEKSUMS_FILE" ]]
then
    # It's okay if user requested to delete it
    # Hint: Even if user doesn't request to calculate checksum the old checksums file will be deleted to avoid mistakes!
    if [[ "$CLEAN_OUTPUT" == true ]]
    then
        echo -n "Removing checksums file... "
        rm "$CHEKSUMS_FILE" > /dev/null 2>&1
        if [ $? != 0 ]
        then
            echo "failed."
            exit 19
        fi
        echo "done."
    else
        # User have to delete the checksums file manually or enter the --clean argument
        echo "Output cheksums file file exists. Please, remove it manually to generate a new one."
        exit 20
    fi
fi
# Calculating a new checksum only if the user requested
if [[ "$CALCULATE_CHECKSUM" == true ]]
then
    echo -n "Calculating checksum... "
    # Calculating checksum using md5sums and redirecting results to the file
    md5sum "$OUTPUT_TARBALL" > "$CHEKSUMS_FILE" 2>&1
    if [ $? != 0 ]
    then
        echo "failed."
        exit 21
    fi
    echo "done."
fi

echo -n "Cleaning up... "
# Forming a list from web source files, makefile web file and included Web files
CLEENUP_FILE_LIST=( "${BASE_FILES_WEB[@]}" "${SOURCES_WEB_FILES[@]}" "${INCLUDED_WEB_FILES[@]}" )
# Removing all downloaded web files
for file in "${CLEENUP_FILE_LIST[@]}"
do
    rm "$file" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        echo "failed."
        exit 22
    fi
done
echo "done."
