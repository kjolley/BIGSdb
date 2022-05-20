--This file can be used to modify an isolate database to enable GPS lookups of
--a location field, such as town, so that it can be used in mapping. It 
--requires PostGIS to be installed.

CREATE EXTENSION postgis;

CREATE TABLE geography_point_lookup (
id bigserial NOT NULL,
country_code text NOT NULL,
field text NOT NULL,
value text NOT NULL,
location geography(POINT, 4326) NOT NULL,
datestamp date NOT NULL,
curator int NOT NULL,
PRIMARY KEY (id),
UNIQUE (country_code,field,value),
CONSTRAINT gl_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

GRANT USAGE, SELECT ON SEQUENCE geography_point_lookup_id_seq TO apache;
GRANT SELECT,UPDATE,INSERT,DELETE ON geography_point_lookup TO apache;
