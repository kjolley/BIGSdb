ALTER TABLE schemes ADD allow_presence boolean;
UPDATE schemes SET allow_presence = FALSE;
