#!/usr/bin/env bash

#
# Usage:
#   ./copydb sample.cfg
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

if [ ! -f ${DBD_PATH} ]; then
    echo "dbd script not found at the specified path."
    exit
fi

VALID_TARGETS=('local' 'docker' 'backup')

if ! grep -q $DESTINATION_TARGET <<< "${VALID_TARGETS[@]}"
then
    echo 'You have selected an invalid destination target'
fi

# define a couple of variables
TIMESTAMP=$(date +"%Y%m%dT%H%M%S")
DESTINATION_DB_NAME=${DBD_DATABASE_ID}"_"${TIMESTAMP}

grn=$'\e[1;32m'
end=$'\e[0m'

if [ $DESTINATION_TARGET == "local" ]; then
  
    printf "\n%s\n" "${grn}Creating new database${end}"
    mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} -e "CREATE DATABASE ${DESTINATION_DB_NAME}"

    printf "\n%s\n" "${grn}Downloading and importing database${end}"
    ${DBD_PATH} ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} --exclude-table-data ${EXCLUDED_TABLES}  | gunzip | mysql -u ${DESTINATION_DB_USER} -p${DESTINATION_DB_PASS} ${DESTINATION_DB_NAME}

    printf "\n${grn}The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"

elif [ $DESTINATION_TARGET == "docker" ]; then

    printf "\n%s\n" "${grn}Spinning up a new docker container${end}"

    INSTANCE_NAME="copydb_"${TIMESTAMP}

    MYSQL_CONTAINER=`docker run -td --name ${INSTANCE_NAME} --health-cmd='mysqladmin ping --silent' -p 3306 -e MYSQL_ROOT_PASSWORD=${DOCKER_ROOT_PASSWORD} -d ${DOCKER_TAG} --max-allowed-packet=67108864 --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`

    while ! docker exec ${INSTANCE_NAME} mysqladmin --user=root --password=${DOCKER_ROOT_PASSWORD} --host "127.0.0.1" ping --silent &> /dev/null ; do
        echo "Waiting for a database connection..."
        sleep 1
    done

    printf "\n${grn}Docker is now running${end}\n"

    printf "\n%s\n" "${grn}Creating a new database${end}"
    docker exec -it ${INSTANCE_NAME} mysql -uroot -p${DOCKER_ROOT_PASSWORD} -e "CREATE DATABASE ${DESTINATION_DB_NAME};"

    printf "\n%s\n" "${grn}Downloading the database${end}"
    ${DBD_PATH} ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} --exclude-table-data ${EXCLUDED_TABLES} > "${INSTANCE_NAME}.sql.gz"

    printf "\n%s\n" "${grn}Importing the database${end}"

    # use pv for visual progress
    pv "${INSTANCE_NAME}.sql.gz" | gunzip | docker exec -i ${INSTANCE_NAME} mysql -uroot -p${DOCKER_ROOT_PASSWORD} ${DESTINATION_DB_NAME}

    # remove the backup
    rm "${INSTANCE_NAME}.sql.gz"

    printf "\n${grn}Docker instance name is \"${end}$INSTANCE_NAME${grn}\".${end}\n"
    
    printf "\n${grn}Ports you can use: ${end}\n"
    docker port ${INSTANCE_NAME}

    printf "\n${grn}Database credentials: root / ${DOCKER_ROOT_PASSWORD} ${end}\n"

    printf "\n${grn}The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"

elif [ $DESTINATION_TARGET == "backup" ]; then

    # add forward slash at the end if not found
    #[[ "${BACKUP_PATH}" != */ ]] && BACKUP_PATH="${BACKUP_PATH}/"

    FILE_PATH="${BACKUP_PATH}${DESTINATION_DB_NAME}.sql.gz"

    # run dbd and save the file within the configured location
    ${DBD_PATH} ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} --exclude-table-data ${EXCLUDED_TABLES} > ${FILE_PATH}

fi
