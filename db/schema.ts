import {sqliteTable, text, integer, index} from 'drizzle-orm/sqlite-core';
export const projects=sqliteTable('projects',{
 id:text('id').primaryKey(), title:text('title').notNull(), client:text('client').notNull(),
 location:text('location').notNull(), progress:integer('progress').notNull().default(0),
 status:text('status').notNull().default('Préparation'), codeHash:text('code_hash').unique(),
 accessVersion:integer('access_version').notNull().default(1), active:integer('active').notNull().default(1),
 createdAt:integer('created_at').notNull(), updatedAt:integer('updated_at').notNull()
});
export const sessions=sqliteTable('sessions',{
 hash:text('hash').primaryKey(), projectId:text('project_id').notNull().references(()=>projects.id),
 version:integer('version').notNull(), expires:integer('expires').notNull()
},t=>[index('sessions_expiry').on(t.expires),index('sessions_project').on(t.projectId)]);
export const adminSessions=sqliteTable('admin_sessions',{
 hash:text('hash').primaryKey(), expires:integer('expires').notNull(), credentialVersion:text('credential_version').notNull()
},t=>[index('admin_sessions_expiry').on(t.expires)]);
export const updates=sqliteTable('updates',{
 id:text('id').primaryKey(), projectId:text('project_id').notNull().references(()=>projects.id),
 body:text('body').notNull(), createdAt:integer('created_at').notNull()
},t=>[index('updates_project_date').on(t.projectId,t.createdAt)]);
export const photos=sqliteTable('photos',{
 id:text('id').primaryKey(), projectId:text('project_id').notNull().references(()=>projects.id),
 objectKey:text('object_key').notNull(), caption:text('caption').notNull(),
 mime:text('mime').notNull(), size:integer('size').notNull(), createdAt:integer('created_at').notNull()
},t=>[index('photos_project_date').on(t.projectId,t.createdAt)]);
export const limits=sqliteTable('limits',{
 key:text('key').primaryKey(), count:integer('count').notNull(), expires:integer('expires').notNull()
},t=>[index('limits_expiry').on(t.expires)]);
