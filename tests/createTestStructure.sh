#!/bin/bash

source /scripts/config.sh

rm -rf ${archive_dir}/*

for i in {1..1200};
do
    dir="${archive_dir}/$(date -d -${i}days +${dir_date_pattern})"
    mkdir $dir
    touch -a -m -t $(date -d -${i}days +%Y%m%d%H%M) $dir
done