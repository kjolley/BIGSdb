ALTER TABLE eav_fields ADD conditional_formatting text;
ALTER TABLE eav_fields ADD html_link_text text;
ALTER TABLE eav_fields ADD html_message text;
ALTER TABLE eav_fields ADD no_curate boolean;
UPDATE eav_fields SET no_curate = FALSE;
ALTER TABLE eav_fields ALTER COLUMN no_curate SET NOT NULL;

DROP VIEW merged_project_users;

CREATE VIEW merged_project_users AS SELECT project_id,user_id,bool_or(admin) AS admin,bool_or(modify) AS modify 
FROM (SELECT project_id,user_id,admin,modify FROM project_users UNION ALL SELECT project_id,user_id,false,modify 
FROM project_user_groups AS pug JOIN user_group_members ugm ON pug.user_group=ugm.user_group) AS merged 
GROUP BY project_id,user_id;

GRANT SELECT ON merged_project_users TO apache;

ALTER TABLE projects ADD restrict_user boolean;
ALTER TABLE projects ADD restrict_usergroup boolean;
UPDATE projects SET restrict_user = FALSE;
ALTER TABLE projects ALTER COLUMN restrict_user SET NOT NULL;
UPDATE projects SET restrict_usergroup = FALSE;
ALTER TABLE projects ALTER COLUMN restrict_usergroup SET NOT NULL;
