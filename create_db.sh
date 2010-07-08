#!/bin/bash

# Default PostgreSQL install when compiled from source on a UNIX-like system
PGBIN=/usr/local/pgsql/bin

DBNAME=uncertain_emr
NUMPATIENTS=10000
# I need to run 32-bit python on my Mac because I'm running 32-bit Postgres
#PYTHON_EXE=python-32
PYTHON_EXE=python

$PGBIN/dropdb $DBNAME;
$PGBIN/createdb $DBNAME;

$PGBIN/psql $DBNAME < db_creation.sql

$PYTHON_EXE populate_db.py $DBNAME $NUMPATIENTS

$PGBIN/psql $DBNAME < index_creation.sql
