#!/bin/bash

if [ $1 = "dmd" ]; then
	cd src
	dmd -debug -gs -g -ofmain `ls *.d` -L-L. $@
	cd ..
fi

if [ $1 = "dmdprof" ]; then
	dmd -profile -profile=gc -debug -gs -g -ofmain `ls ./src/*.d` -L-L. $@
	echo " * deleting old trace log files because they're cumulative."
	rm trace.log >> /dev/null 2>&1
	rm trace.def >> /dev/null 2>&1
	rm profilegc.log >> /dev/null 2>&1
fi

if [ $1 = "ldc" ]; then
	ldc2 -wi -d-debug -stats -ofmain `ls ./src/*.d` -L-L/usr/local/lib/ -L-L. $@
fi
