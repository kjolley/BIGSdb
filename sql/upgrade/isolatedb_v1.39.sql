CREATE TABLE assembly_submissions (
submission_id text NOT NULL,
index int NOT NULL,
isolate_id int NOT NULL,
isolate text NOT NULL,
sequence_method text NOT NULL,
filename text NOT NULL,
PRIMARY KEY(submission_id,isolate_id),
CONSTRAINT ags_submission_id FOREIGN KEY (submission_id) REFERENCES submissions
ON DELETE CASCADE
ON UPDATE CASCADE
);

GRANT SELECT,UPDATE,INSERT,DELETE ON assembly_submissions TO apache;
