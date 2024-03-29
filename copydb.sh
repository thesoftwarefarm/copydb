#!/usr/bin/env bash

#
# Usage:
#   ./copydb.sh sample.cfg
#

# check if a config file has been provided
if [ $# -eq 0 ]; then
    echo "No arguments supplied."
    exit
fi

if [ -f $1 ]; then
    source $1
else
    printf "%s\n" "Config file not found."
    exit
fi

if ! command -v dbd &> /dev/null
then
    echo "dbd could not be found, please install it first (https://github.com/serbanrobu/dbd)"
    exit
fi

VALID_TARGETS=('local' 'docker' 'backup' 'remote' 'cloud')

if ! grep -q $DESTINATION_TARGET <<< "${VALID_TARGETS[@]}"
then
    echo 'You have selected an invalid destination target'
    exit
fi

# we need pv to be found within PATH, otherwise we'll do a lot of steps only to error out
# pv is required only for local and docker
if [ $DESTINATION_TARGET == "local" ] | [ $DESTINATION_TARGET == "docker" ]
then
    if ! command -v pv &> /dev/null
    then
        echo "pv could not be found, please install it first (on MacOS: brew install pv)"
        exit
    fi
fi

if ([ $DESTINATION_TARGET == "cloud" ] && [ -z $CLOUD_HOSTNAME ] )
then
    echo "Cloud hostname is missing."
    exit
fi

# define a couple of variables
TIMESTAMP=$(date +"%Y%m%dT%H%M%S")
DROP_DATABASE_AND_RECREATE=false

if [ -z "$DATABASE_NAME" ]
then
      DESTINATION_DB_NAME=${DBD_DATABASE_ID}"_"${TIMESTAMP}
else
      DESTINATION_DB_NAME=$DATABASE_NAME
      DROP_DATABASE_AND_RECREATE=true
fi

grn=$'\e[1;32m'
end=$'\e[0m'

# excluded tables might be missing, in which case dbd will complain
if [ -z "$EXCLUDED_TABLES" ]
then
      EXCLUDE_TABLES_PART=""
else
      EXCLUDE_TABLES_PART="--exclude-table-data ${EXCLUDED_TABLES}"
fi

if [ $DESTINATION_TARGET == "cloud" ]; then

    if [ "$DROP_DATABASE_AND_RECREATE" = true ]
    then
        printf "\n%s\n" "${grn}Dropping the existing database${end}"
        mysql -h ${CLOUD_HOSTNAME} -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} -e "DROP DATABASE IF EXISTS ${DESTINATION_DB_NAME}"
    fi

    printf "\n%s\n" "${grn}Creating new database${end}"
    mysql -h ${CLOUD_HOSTNAME} -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} -e "CREATE DATABASE ${DESTINATION_DB_NAME}"

    printf "\n%s\n" "${grn}Downloading the database${end}"
    dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > /tmp/"${DESTINATION_DB_NAME}.sql.gz" 
    
    printf "\n%s\n" "${grn}Importing the database${end}"
    pv /tmp/"${DESTINATION_DB_NAME}.sql.gz" | gunzip | mysql -h ${CLOUD_HOSTNAME} -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} ${DESTINATION_DB_NAME}

    printf "\n%s\n" "${grn}Cleaning up${end}"
    rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    printf "\n${grn}The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"

elif [ $DESTINATION_TARGET == "local" ]; then

    if [ "$DROP_DATABASE_AND_RECREATE" = true ]
    then
        printf "\n%s\n" "${grn}Dropping the existing database${end}"
        mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} -e "DROP DATABASE IF EXISTS ${DESTINATION_DB_NAME}"
    fi

    printf "\n%s\n" "${grn}Creating new database${end}"
    mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} -e "CREATE DATABASE ${DESTINATION_DB_NAME}"

    printf "\n%s\n" "${grn}Downloading the database${end}"
    dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > /tmp/"${DESTINATION_DB_NAME}.sql.gz" 
    
    printf "\n%s\n" "${grn}Importing the database${end}"
    pv /tmp/"${DESTINATION_DB_NAME}.sql.gz" | gunzip | mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} ${DESTINATION_DB_NAME}

    printf "\n%s\n" "${grn}Cleaning up${end}"
    rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    printf "\n${grn}The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"

elif [ $DESTINATION_TARGET == "docker" ]; then

    printf "\n%s\n" "${grn}Spinning up a new docker container${end}"

    if [ "$DOCKER_NEW_INSTANCE" = true ]
    then
        INSTANCE_NAME="copydb_"${TIMESTAMP}
        docker run -td --name ${INSTANCE_NAME} --health-cmd='mysqladmin ping --silent' -p 3306 -e MYSQL_ROOT_PASSWORD=${DESTINATION_DB_PASS} -d ${DOCKER_TAG} --max-allowed-packet=67108864 --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    else
        INSTANCE_NAME="$DOCKER_EXISTING_INSTANCE_NAME"
    fi

    while ! docker exec ${INSTANCE_NAME} mysqladmin --user=root --password=${DESTINATION_DB_PASS} --host "127.0.0.1" ping --silent &> /dev/null ; do
        echo "Waiting for a database connection..."
        sleep 1
    done

    printf "\n${grn}Docker is now running${end}\n"

    if [ "$DROP_DATABASE_AND_RECREATE" = true ]
    then
        printf "\n%s\n" "${grn}Dropping the existing database${end}"
        docker exec -it ${INSTANCE_NAME} mysql -uroot -p${DESTINATION_DB_PASS} -e "DROP DATABASE IF EXISTS ${DESTINATION_DB_NAME};"
    fi

    printf "\n%s\n" "${grn}Creating a new database${end}"
    docker exec -it ${INSTANCE_NAME} mysql -uroot -p${DESTINATION_DB_PASS} -e "CREATE DATABASE ${DESTINATION_DB_NAME};"

    printf "\n%s\n" "${grn}Downloading the database within /tmp/ ${end}"
    dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    printf "\n%s\n" "${grn}Importing the database${end}"

    pv /tmp/"${DESTINATION_DB_NAME}.sql.gz" | gunzip | docker exec -i ${INSTANCE_NAME} mysql -uroot -p${DESTINATION_DB_PASS} ${DESTINATION_DB_NAME}

    printf "\n%s\n" "${grn}Cleaning up${end}"
    rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    printf "\n${grn}Docker instance name is \"${end}$INSTANCE_NAME${grn}\".${end}\n"
    
    printf "\n${grn}Ports you can use: ${end}\n"
    docker port ${INSTANCE_NAME}

    printf "\n${grn}Database credentials: root / \"${end}$DESTINATION_DB_PASS${grn}\".${end}\n"

    printf "\n${grn}The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"

elif [ $DESTINATION_TARGET == "backup" ]; then

    FILE_PATH="${BACKUP_PATH}/${DESTINATION_DB_NAME}.sql.gz"

    dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > ${FILE_PATH}

elif [ $DESTINATION_TARGET == "remote" ]; then

    # when checking if we can connect to remote host, use:
    # - StrictHostKeyChecking to automatically accept host keys
    # - LogLevel=ERROR to suppress the warning when the host key is missing and is automatically added.
    status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o LogLevel=ERROR ${REMOTE_USER}@${REMOTE_IP} echo ok 2>&1)

    if [[ $status == ok ]] ; then
        
        printf "\n%s\n" "${grn}Downloading the database locally${end}"
        dbd ${DBD_CONNECTION_ID} --dbname ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} ${EXCLUDE_TABLES_PART} > /tmp/"${DESTINATION_DB_NAME}.sql.gz"

        printf "\n%s\n" "${grn}Transferring to remote host${end}"
        scp /tmp/"${DESTINATION_DB_NAME}.sql.gz" ${REMOTE_USER}@${REMOTE_IP}:/tmp/"${DESTINATION_DB_NAME}.sql.gz"

        DROP_DATABASE_SEQUENCE=""
        if [ "$DROP_DATABASE_AND_RECREATE" = true ]
        then
            DROP_DATABASE_SEQUENCE="mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} -e \"DROP DATABASE IF EXISTS ${DESTINATION_DB_NAME}\""
        fi

        printf "\n%s\n" "${grn}Running commands on remote host${end}"
        ssh ${REMOTE_USER}@${REMOTE_IP} << EOF
 
 echo "Dropping database if required" 
 ${DROP_DATABASE_SEQUENCE}
 
 echo "Creating database"       
 mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} -e "CREATE DATABASE ${DESTINATION_DB_NAME}"

 echo "Importing database"
 pv /tmp/"${DESTINATION_DB_NAME}.sql.gz" | gunzip | mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} ${DESTINATION_DB_NAME}

 echo "Clean up"
 rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

EOF

        printf "\n%s\n" "${grn}Local clean up${end}"
        rm /tmp/"${DESTINATION_DB_NAME}.sql.gz"

    else
        echo "Error when then trying to remotely login:"
        echo $status
        exit
    fi

fi
