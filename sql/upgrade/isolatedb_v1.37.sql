ALTER TABLE sequence_flags ADD CONSTRAINT sf_curator FOREIGN KEY (curator) REFERENCES users 
ON DELETE NO ACTION
ON UPDATE CASCADE;