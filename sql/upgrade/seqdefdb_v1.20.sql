CREATE TABLE client_dbase_cschemes (
client_dbase_id int NOT NULL,
cscheme_id int NOT NULL,
client_cscheme_id int,
curator int NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (client_dbase_id,cscheme_id),
CONSTRAINT cdc_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE,
CONSTRAINT cdc_client_dbase_id FOREIGN KEY (client_dbase_id) REFERENCES client_dbases
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT cdc_cscheme_id FOREIGN KEY (cscheme_id) REFERENCES classification_schemes
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON client_dbase_cschemes TO apache;

ALTER TABLE schemes ADD max_missing int;
