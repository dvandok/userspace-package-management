#!/bin/sh

glite-wms-job-perusal --get -f stdout `tail -1 site-pkgtool.jids`
