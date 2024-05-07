UPDATE db_attributes SET value='46' WHERE field='version';

ALTER TABLE query_interface_fields ADD CONSTRAINT qif_id FOREIGN KEY (id) REFERENCES query_interfaces(id) 
ON DELETE CASCADE
ON UPDATE CASCADE;
