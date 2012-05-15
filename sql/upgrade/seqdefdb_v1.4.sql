ALTER TABLE user_permissions DROP COLUMN set_user_permissions;

CREATE TABLE allele_flags (
locus text NOT NULL,
allele_id text NOT NULL,
flag text NOT NULL,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY(locus,allele_id,flag),
CONSTRAINT af_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT af_locus_allele_id FOREIGN KEY(locus,allele_id) REFERENCES sequences
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON allele_flags TO apache;

-- Snapshot materialized view SQL written by Jonathan Gardner
-- http://tech.jonathangardner.net/wiki/PostgreSQL/Materialized_Views

CREATE LANGUAGE 'plpgsql';

CREATE TABLE matviews (
  mv_name NAME NOT NULL PRIMARY KEY,
  v_name NAME NOT NULL,
  last_refresh TIMESTAMP WITH TIME ZONE
);
GRANT SELECT,UPDATE,INSERT,DELETE ON matviews TO apache;

CREATE OR REPLACE FUNCTION create_matview(NAME, NAME)
 RETURNS VOID
 SECURITY DEFINER
 LANGUAGE plpgsql AS '
 DECLARE
     matview ALIAS FOR $1;
     view_name ALIAS FOR $2;
     entry matviews%ROWTYPE;
 BEGIN
     SELECT * INTO entry FROM matviews WHERE mv_name = matview;
 
     IF FOUND THEN
         RAISE EXCEPTION ''Materialized view ''''%'''' already exists.'',
           matview;
     END IF;
 
     EXECUTE ''REVOKE ALL ON '' || view_name || '' FROM PUBLIC''; 
 
     EXECUTE ''GRANT SELECT ON '' || view_name || '' TO PUBLIC'';
 
     EXECUTE ''CREATE TABLE '' || matview || '' AS SELECT * FROM '' || view_name;
 
     EXECUTE ''REVOKE ALL ON '' || matview || '' FROM PUBLIC'';
 
     EXECUTE ''GRANT SELECT ON '' || matview || '' TO PUBLIC'';

     INSERT INTO matviews (mv_name, v_name, last_refresh)
       VALUES (matview, view_name, CURRENT_TIMESTAMP); 
     
     RETURN;
 END
 ';
 
ALTER FUNCTION create_matview(NAME, NAME) OWNER TO apache;
 
CREATE OR REPLACE FUNCTION drop_matview(NAME) RETURNS VOID
 SECURITY DEFINER
 LANGUAGE plpgsql AS '
 DECLARE
     matview ALIAS FOR $1;
     entry matviews%ROWTYPE;
 BEGIN
 
     SELECT * INTO entry FROM matviews WHERE mv_name = matview;
 
     IF NOT FOUND THEN
         RAISE EXCEPTION ''Materialized view % does not exist.'', matview;
     END IF;
 
     EXECUTE ''DROP TABLE '' || matview;
     DELETE FROM matviews WHERE mv_name=matview;
 
     RETURN;
 END
 ';
 
 CREATE OR REPLACE FUNCTION refresh_matview(name) RETURNS VOID
 SECURITY DEFINER
 LANGUAGE plpgsql AS '
 DECLARE 
     matview ALIAS FOR $1;
     entry matviews%ROWTYPE;
 BEGIN
 
     SELECT * INTO entry FROM matviews WHERE mv_name = matview;
 
     IF NOT FOUND THEN
         RAISE EXCEPTION ''Materialized view % does not exist.'', matview;
    END IF;

    EXECUTE ''DELETE FROM '' || matview;
    EXECUTE ''INSERT INTO '' || matview
        || '' SELECT * FROM '' || entry.v_name;

    UPDATE matviews
        SET last_refresh=CURRENT_TIMESTAMP
        WHERE mv_name=matview;

    RETURN;
END
';
