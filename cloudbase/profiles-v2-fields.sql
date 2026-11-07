-- DriveTrack 云端二期 v2：profiles 表加公开资料扩展字段
--
-- 用法：控制台 → 数据库 → SQL 编辑器，把全文粘贴执行。
-- 全部语句可重复执行（ADD COLUMN IF NOT EXISTS）。
-- 前置：已跑过 cloudbase/profiles-public.sql（profiles 表已存在）。
-- 对应 App 侧：PublicProfile 的 gender / birthday / industry /
-- vehicle_brand / vehicle_model（见 lib/cloud_service.dart 的
-- toRow/fromJson，v1.5.1 起随昵称/简介一起同步）。
--
-- 注意：新列必须先建好再发含新字段的 App 版，否则 upsert 会因
-- 列不存在报 400、资料保存失败。
--
-- RLS 策略不用动：同一张表、同一批策略（读公开、写只放行本人）
-- 自动覆盖新列；GRANT 也不用动（表级授权已含全部列）。

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS gender varchar(8) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS birthday varchar(16) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS industry varchar(64) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS vehicle_brand varchar(64) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS vehicle_model varchar(64) NOT NULL DEFAULT '';
