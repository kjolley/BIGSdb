CREATE TABLE authors (
id serial NOT NULL UNIQUE,
surname varchar NOT NULL,
initials varchar NOT NULL,
PRIMARY KEY (id)
);

CREATE UNIQUE INDEX index_authors ON authors (surname,initials);


CREATE TABLE refs (
pmid INTEGER NOT NULL UNIQUE,
year INTEGER NOT NULL,
journal varchar NOT NULL,
volume varchar NOT NULL,
pages varchar NOT NULL,
title varchar NOT NULL,
abstract varchar NOT NULL,
PRIMARY KEY (pmid)
);

CREATE TABLE refauthors (
pmid INTEGER NOT NULL,
author INTEGER NOT NULL,
position INTEGER NOT NULL,
PRIMARY KEY (pmid,author,position),
CONSTRAINT pmid FOREIGN KEY (pmid) references refs ON DELETE CASCADE ON UPDATE CASCADE,
CONSTRAINT author FOREIGN KEY (author) references authors ON DELETE NO ACTION ON UPDATE CASCADE
);

GRANT SELECT ON authors,refs,refauthors TO apache;
