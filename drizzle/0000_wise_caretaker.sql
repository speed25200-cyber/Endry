CREATE TABLE `admin_sessions` (
	`hash` text PRIMARY KEY NOT NULL,
	`expires` integer NOT NULL,
	`credential_version` text NOT NULL
);
--> statement-breakpoint
CREATE INDEX `admin_sessions_expiry` ON `admin_sessions` (`expires`);--> statement-breakpoint
CREATE TABLE `limits` (
	`key` text PRIMARY KEY NOT NULL,
	`count` integer NOT NULL,
	`expires` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `limits_expiry` ON `limits` (`expires`);--> statement-breakpoint
CREATE TABLE `photos` (
	`id` text PRIMARY KEY NOT NULL,
	`project_id` text NOT NULL,
	`object_key` text NOT NULL,
	`caption` text NOT NULL,
	`mime` text NOT NULL,
	`size` integer NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `photos_project_date` ON `photos` (`project_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `projects` (
	`id` text PRIMARY KEY NOT NULL,
	`title` text NOT NULL,
	`client` text NOT NULL,
	`location` text NOT NULL,
	`progress` integer DEFAULT 0 NOT NULL,
	`status` text DEFAULT 'Préparation' NOT NULL,
	`code_hash` text,
	`access_version` integer DEFAULT 1 NOT NULL,
	`active` integer DEFAULT 1 NOT NULL,
	`created_at` integer NOT NULL,
	`updated_at` integer NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX `projects_code_hash_unique` ON `projects` (`code_hash`);--> statement-breakpoint
CREATE TABLE `sessions` (
	`hash` text PRIMARY KEY NOT NULL,
	`project_id` text NOT NULL,
	`version` integer NOT NULL,
	`expires` integer NOT NULL,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `sessions_expiry` ON `sessions` (`expires`);--> statement-breakpoint
CREATE INDEX `sessions_project` ON `sessions` (`project_id`);--> statement-breakpoint
CREATE TABLE `updates` (
	`id` text PRIMARY KEY NOT NULL,
	`project_id` text NOT NULL,
	`body` text NOT NULL,
	`created_at` integer NOT NULL,
	FOREIGN KEY (`project_id`) REFERENCES `projects`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `updates_project_date` ON `updates` (`project_id`,`created_at`);