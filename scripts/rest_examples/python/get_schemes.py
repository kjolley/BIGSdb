#!/usr/bin/env python3
#Example script to list names and URIs of scheme definitions using the
#PubMLST RESTful API.
#Written by Keith Jolley
#Copyright (c) 2017, University of Oxford
#E-mail: keith.jolley@zoo.ox.ac.uk
#
#This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
#BIGSdb is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.
#
#BIGSdb is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.

import requests, re, argparse
parser = argparse.ArgumentParser()
parser.add_argument('--exclude', help='scheme name must not include provided term')
parser.add_argument('--match', help='scheme name must include provided term')
args = parser.parse_args()

def main():
    base_uri = 'http://rest.pubmlst.org'
    resources = requests.get(base_uri).json()
    for resource in resources:
        if resource['databases']:
            for db in resource['databases']:
                get_matching_schemes(db)

def get_matching_schemes(db):
    if re.search(r'definitions',db['description'],flags=0):
        db_attributes = requests.get(db['href']).json()
        if not 'schemes' in db_attributes.keys(): return
        schemes = requests.get(db_attributes['schemes']).json()
        for scheme in schemes['schemes']:
            if args.match:
                if not re.search(args.match,scheme['description'],flags=0):continue 
            if args.exclude:
                if re.search(args.exclude,scheme['description'],flags=0):continue
            output = "%s\t%s\t%s" % (db['description'],scheme['description'],scheme['scheme'])
            print (output)
    return

if __name__ == "__main__":
    main()
