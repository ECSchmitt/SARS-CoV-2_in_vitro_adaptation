#! /bin/bash

#fetch data
prefetch --option-file $1

#load accession list, iterate over all experiments and get the fastq-files

while IFS= read -r line
do
	echo "$line"
	cd $line
        mv $line.sra ..
        cd ..
	fasterq-dump --split-files $line.sra
	rm -r $line
	rm *.sra

done < "$1"
