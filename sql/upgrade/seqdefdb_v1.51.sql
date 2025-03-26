UPDATE db_attributes SET value='51' WHERE field='version';

ALTER TABLE users ADD country text;
ALTER TABLE users ADD sector text;
