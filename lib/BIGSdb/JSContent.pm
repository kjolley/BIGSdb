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

sub get_ol_arcgis_world_imagery_layer {
	return << "JS";
	new ol.layer.Tile({
    	visible: false,
        source: new ol.source.XYZ({
        	attributions: ['Powered by Esri;','Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community'],
            attributionsCollapsible: true,
            url: 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            maxZoom: 23          	
        })
	})
JS
}

sub get_ol_arcgis_hybdrid_ref_layer {
	return << "JS";
	new ol.layer.VectorTile({
		visible: false,
		source: new ol.source.VectorTile({
			format: new ol.format.MVT({
				layers: ['Boundary line','Admin0 point','City small scale','City large scale']
			}),
			url: 'https://basemaps.arcgis.com/arcgis/rest/services/World_Basemap_v2/VectorTileServer/tile/{z}/{y}/{x}.pbf',
		}),
		style: function(feature, resolution) {
			var zoom = map.getView().getZoomForResolution(resolution);
			if (feature.get('layer') == 'Admin0 point' && zoom <= 5){
				return new ol.style.Style({
					text: new ol.style.Text({
						text: feature.get('_name'), 
						font: '14px sans-serif',
						fill: new ol.style.Fill({
							color: '#aaa',
						}),
						stroke: new ol.style.Stroke({
							color: '#000',
							width: 3
						})
					})
				});
			}
			if (feature.get('layer') == 'City small scale' || feature.get('layer') == 'City large scale'){
				return new ol.style.Style({
					text: new ol.style.Text({
						text: feature.get('_name'), 
						font: '11px sans-serif',
						fill: new ol.style.Fill({
							color: '#aaa',
						}),
						stroke: new ol.style.Stroke({
							color: '#000',
							width: 2
						})
					})
				});
			}
			if (feature.get('layer') == 'Boundary line' ){
				return new ol.style.Style({
					stroke: new ol.style.Stroke({
						color: '#aaa',
						width: 1
					})
				});
			}
		}
	})
JS
}
1;
