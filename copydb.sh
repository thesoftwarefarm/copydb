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

else

    printf "\n%s\n" "${grn}Spinning up a new docker container${end}"

    INSTANCE_NAME="copydb_"${TIMESTAMP}

    MYSQL_CONTAINER=`docker run -td --name ${INSTANCE_NAME} --health-cmd='mysqladmin ping --silent' -p 3306 -e MYSQL_ROOT_PASSWORD=my-secret-pw -d ${DOCKER_TAG}`

    while ! docker exec ${INSTANCE_NAME} mysqladmin --user=root --password=my-secret-pw --host "127.0.0.1" ping --silent &> /dev/null ; do
        echo "Waiting for database connection..."
        sleep 1
    done

    printf "\n${grn}Docker is now running${end}\n\n"

    printf "\n%s\n" "${grn}Creating new database${end}"
    docker exec -it ${INSTANCE_NAME} mysql -uroot -pmy-secret-pw -e "CREATE DATABASE ${DESTINATION_DB_NAME};"

    printf "\n%s\n" "${grn}Downloading database${end}"
    ${DBD_PATH} ${DBD_DATABASE_ID} --api-key ${DBD_API_KEY} --url ${DBD_URL} --exclude-table-data ${EXCLUDED_TABLES} > "${INSTANCE_NAME}.sql.gz"

    printf "\n%s\n" "${grn}Importing database${end}"

    gunzip < "${INSTANCE_NAME}.sql.gz" | docker exec -i ${INSTANCE_NAME} mysql -uroot -pmy-secret-pw ${DESTINATION_DB_NAME}

    rm "${INSTANCE_NAME}.sql.gz"

    printf "\n${grn}New docker instance name is \"${end}$INSTANCE_NAME${grn}\".${end}\n\n"

fi

printf "\n${grn}Done. The copied database name is \"${end}$DESTINATION_DB_NAME${grn}\".${end}\n\n"
