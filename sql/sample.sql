CREATE TABLE samples (
isolate_id integer NOT NULL,
sample_id integer NOT NULL,
sample_type text NOT NULL,
freezer text NOT NULL,
box integer NOT NULL,
curator int NOT NULL,
comments text,
date_entered date NOT NULL,
datestamp date NOT NULL,
PRIMARY KEY (isolate_id,sample_id),
CONSTRAINT s_isolate_id FOREIGN KEY (isolate_id) REFERENCES isolates
ON DELETE CASCADE
ON UPDATE CASCADE,
CONSTRAINT s_curator FOREIGN KEY (curator) REFERENCES users
ON DELETE NO ACTION
ON UPDATE CASCADE
);

CREATE INDEX si_isolate_id ON samples (isolate_id);
GRANT SELECT,UPDATE,INSERT,DELETE ON samples TO apache;
