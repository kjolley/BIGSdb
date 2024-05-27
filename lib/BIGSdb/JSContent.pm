#Written by Keith Jolley
#Copyright (c) 2024, University of Oxford
#E-mail: keith.jolley@biology.ox.ac.uk
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
#
#You should have received a copy of the GNU General Public License
#along with BIGSdb.  If not, see <http://www.gnu.org/licenses/>.
package BIGSdb::JSContent;
use strict;
use warnings;
use 5.010;

sub get_ol_osm_layer {
	return << "JS";
	new ol.layer.Tile({
    	visible: true,
        source: new ol.source.OSM({
        	crossOrigin: null,
   	 	})
    })
JS
}

sub get_ol_maptiler_map_layer {
	my ($api_key) = @_;
	my $attributions = q(<img src="https://api.maptiler.com/resources/logo.svg" alt="MapTiler logo" style="margin-right:20px">)
	. q(<a href="https://www.maptiler.com/copyright/" target="_blank">&copy; MapTiler</a>);
	return << "JS";
	new ol.layer.Tile({
    	visible: false,
        source: new ol.source.TileJSON({
        	attributions: '$attributions',
            attributionsCollapsible: false,
            url: 'https://api.maptiler.com/maps/hybrid/tiles.json?key=$api_key',
            tileSize: 512,
            maxZoom: 20       	
        })
	})
JS
}

1;
