#!/usr/bin/env python3
# Example script to download alleles from a sequence definition database
# Written by Keith Jolley
# Copyright (c) 2017, University of Oxford
# E-mail: keith.jolley@zoo.ox.ac.uk
#
# This file is part of Bacterial Isolate Genome Sequence Database (BIGSdb).
#
# BIGSdb is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# BIGSdb is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

import argparse
import os
import requests

base_uri = 'http://rest.pubmlst.org'

parser = argparse.ArgumentParser()
parser.add_argument('--database', required=True, help='Database configuration name')
parser.add_argument('--dir', help='Output directory')
parser.add_argument('--scheme_id', type=int, help='Only return loci belonging to scheme. If this option is not used then all \
    loci from the database will be downloaded')
args = parser.parse_args()

def main():
    if args.dir and not os.path.exists(args.dir):
        os.makedirs(args.dir)
    dir = args.dir or './'
    url = base_uri + '/db/' + args.database
    r = requests.get(url)
    if r.status_code == 404:
        print('Database ' + args.database + ' does not exist.')
        os._exit(1)
    loci = []
    if args.scheme_id:
        url = base_uri +  '/db/' + args.database + '/schemes/' + str(args.scheme_id);
        r = requests.get(url);
        if r.status_code == 404:
            print('Scheme ' + str(args.scheme_id) + ' does not exist.');
            os._exit(1)
        loci = r.json()['loci']
    else:
        url = base_uri + '/db/' + args.database + '/loci?return_all=1'
        r = requests.get(url);
        loci = r.json()['loci'];
    for locus_path in loci:
        r = requests.get(locus_path)
        locus = r.json()['id']
        if r.json()['alleles_fasta']:
            r = requests.get(r.json()['alleles_fasta'])
            fasta_file = open(dir + '/' + locus + '.fas', 'w')
            fasta_file.write(r.text)
            fasta_file.close()
    return

if __name__ == "__main__":
    main()
