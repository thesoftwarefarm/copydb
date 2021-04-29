# Copying databases

This script will copy a MySql/Postgresql database from the a remote server. 

Connection information is taken from the configuration file provided as a parameter.

The configuration file also specifies the excluded tables in a comma-separated list of table names (`EXCLUDED_TABLES`); these tables' content will not be copied over (only their structure will).

There are a couple of options of what to do with the database dump once it's fetched:

- restore is on the local server
- restore it within a docker instance
- simply create a gzip-ed backup and store it within a custom path
- restore it on a remote server you have access to (be that vagrant or another server). It is assumed you have access via SSH keys and no password is required

## Dependencies

You should have the following:

- database dumper script script: https://github.com/serbanrobu/dbd - go to the releases page, download the appropriate version for your OS, run `chmod +x dbd`, and move it to `/usr/local/bin/dbd` for convencience

- `pv` to display a progress bar for the import process. On macOS, install it with: `brew install pv`

- `docker` installed and running (if going with a docker instance)

## Installation

Clone this repository and make the script executable (`chmod +x copydb.sh`).

## Usage

For MySql:

```
./copydb.sh sample.cfg
```

For Postgresql:

```
./pg-copydb.sh sample.cfg
```

## Multi-tenant systems

Using this script you can orchestrate the download of multiple databases (maybe belonging to a multi-tenant system). Create a bash script and run a sequence like below:

```
./copydb.sh landlord.cfg
./copydb.sh tenant1.cfg
./copydb.sh tenant2.cfg
```

