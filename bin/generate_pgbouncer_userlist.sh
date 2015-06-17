#!/bin/bash

psql -qAtXF' ' -c "select rolname,rolpassword from pg_authid" |sed -e 's/^/\"/' -e 's/$/\"/' -e 's/ /\" \"/'
