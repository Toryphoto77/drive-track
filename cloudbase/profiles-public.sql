-- DriveTrack 云端二期（腾讯 CloudBase PG 模式）公开资料 + 公开行程
--
-- 用法：控制台 → 数据库 → SQL 编辑器，把全文粘贴执行。
-- 全部语句可重复执行（IF NOT EXISTS / ADD COLUMN IF NOT EXISTS /
-- DROP POLICY IF EXISTS）。前置：先跑过 cloudbase/trips-rls.sql
--（public.trips 表与 trip-files 桶策略已存在）。
-- 环境：上海地域、PG 模式（PostgreSQL）。
--
-- 关键点：App 默认是匿名登录，匿名 JWT 的 role 是 anon，但 sub
-- 是真实 user id。所以 GRANT 与策略必须同时覆盖 anon 与
-- authenticated 两个角色——只开 authenticated 会导致匿名用户
-- 读不到公开资料、写不了自己的资料。
--
-- 公开含义（执行前请确认）：profiles 公开读意味着任何拿到环境
-- ID 的人都能读到全部用户的昵称、简介与头像路径，trips 公开读
-- 意味着任何拿到环境 ID 的人都能读到 is_public = true 的行程
-- 摘要与公开桶里的轨迹文件。这是公开资料的固有含义，不另加限制。
-- 不想公开的内容不要设为公开；收回公开 = 把行程改回仅自己可见
-- （App 会把轨迹文件搬回私有桶并删掉公开桶里的旧文件）。

-- ============================================================
-- 1. profiles 表（public schema；PostgREST 自动暴露成
--    https://<env>.api.tcloudbasegateway.com/v1/rdb/rest/profiles）
--    一行 = 一个云端账号的公开资料。user_id 是云端账号 id
--    （auth.uid()），不是本机 profile.json 里的 DT-xxxx。
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  user_id varchar(64) PRIMARY KEY,
  nickname varchar(32) NOT NULL DEFAULT '',
  bio varchar(200) NOT NULL DEFAULT '',
  avatar_path text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now()
);
-- avatar_path：公开桶里的对象路径，形如
-- public-files/<user id>/avatar.jpg；空字符串 = 未设头像。
-- 昵称最多 32 字、简介最多 200 字（App 侧编辑器同样限长）。

-- 行级安全：读公开（任何人），写只放行本人
-- （INSERT / UPDATE / DELETE 的 user_id 必须等于 auth.uid()）。
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles
  TO anon, authenticated;

DROP POLICY IF EXISTS profiles_select_public ON public.profiles;
CREATE POLICY profiles_select_public ON public.profiles
  FOR SELECT TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT TO anon, authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE TO anon, authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS profiles_delete_own ON public.profiles;
CREATE POLICY profiles_delete_own ON public.profiles
  FOR DELETE TO anon, authenticated
  USING (user_id = auth.uid());

-- ============================================================
-- 2. trips 表加 is_public 列 + 公开读策略
--    （原 trips_select_own 等 4 条仅本人策略不动，策略之间是
--    “或”关系：公开行同时满足 own 与 public 两条读策略。）
-- ============================================================
ALTER TABLE public.trips
  ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS trips_public_created_idx
  ON public.trips (is_public, created_at DESC);

DROP POLICY IF EXISTS trips_select_public ON public.trips;
CREATE POLICY trips_select_public ON public.trips
  FOR SELECT TO anon, authenticated
  USING (is_public = true);

-- ============================================================
-- 3. 公开轨迹文件桶 public-files 的 storage.objects 策略
--    （桶本身在控制台新建，名字 public-files，见
--    cloudbase/profiles-public-steps.md；对象路径
--    <user id>/<trip id>.json 或 <user id>/avatar.jpg，
--    第一段目录即 owner）
--    写只放行本人（上传 / 覆盖 / 删除），读公开（任何人可读
--    桶内全部对象，含匿名用户）。私有行程与头像绝不放进这个桶。
-- ============================================================
DROP POLICY IF EXISTS public_files_insert_own ON storage.objects;
CREATE POLICY public_files_insert_own ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    bucket_id = 'public-files'
    AND (storage.foldername(name))[1] = auth.uid()
  );

-- upsert（同路径重传）要走 UPDATE，也要放行本人。
DROP POLICY IF EXISTS public_files_update_own ON storage.objects;
CREATE POLICY public_files_update_own ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (
    bucket_id = 'public-files'
    AND (storage.foldername(name))[1] = auth.uid()
  )
  WITH CHECK (
    bucket_id = 'public-files'
    AND (storage.foldername(name))[1] = auth.uid()
  );

DROP POLICY IF EXISTS public_files_select_public ON storage.objects;
CREATE POLICY public_files_select_public ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'public-files');

DROP POLICY IF EXISTS public_files_delete_own ON storage.objects;
CREATE POLICY public_files_delete_own ON storage.objects
  FOR DELETE TO anon, authenticated
  USING (
    bucket_id = 'public-files'
    AND (storage.foldername(name))[1] = auth.uid()
  );
