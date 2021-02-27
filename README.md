# Copying databases

This script will copy a MySql database from the a server and restore it on the local server or within a docker container. 

Connection information is taken from the configuration file provided as a parameter.

The configuration file also specifies the excluded tables in a comma-separated list of table names (`EXCLUDED_TABLES`); these tables' content will not be copied over (only their structure will).

This script makes use of the database dumper script https://github.com/serbanrobu/dbd

## Installation

Download the dbd script for your distribution.

Move it to a usable path (like /usr/local/bin/dbd).

Clone this repository and make the script executable (`chmod +x copydb`).

If using docker, make sure docker is installed. One container will be created for you, using the version you chosen within the configuration file.

## Usage
```
./copydb sample.cfg
```