# DriveTrack 公开资料 + 公开行程：控制台执行步骤

给协调人：以下步骤全部在腾讯 CloudBase 控制台操作，App 代码侧已写好，
但控制台没执行完之前，App 里的公开资料同步、公开行程查看都会失败
（失败时 App 只报错、不闪退、不丢本地数据）。

环境：上海地域、PG 模式。环境 ID 只存在本地 `.cloudbase-env` 文件里，
不要写进任何聊天记录或文档。

## 前置

- `cloudbase/trips-rls.sql` 已执行过（`public.trips` 表与 `trip-files`
  私有桶策略已存在）。没执行过先执行它，再执行本轮 SQL。

## 步骤 1：新建公开桶 `public-files`

控制台 → 云存储 → Bucket 管理 → 新建 Bucket：

- 名字填 `public-files`；
- 权限选私有（读写均由下面 SQL 里的 `storage.objects` 策略控制：
  本人可写、他人只读；不要选公有写）；
- MIME 白名单留空（默认不限；App 往里放的是 `application/json`
  轨迹文件与 `image/jpeg` / `image/png` 头像）。

注意：传统模式的旧桶不能复用，PG 模式的桶是另一套 pgstore 桶，
必须新建。`trip-files` 私有桶不动，私有行程继续走它。

## 步骤 2：执行 SQL

控制台 → 数据库 → SQL 编辑器，把 `cloudbase/profiles-public.sql`
全文粘贴执行，确认无报错。

它做的事：

- 建 `public.profiles` 表（`user_id` 主键、昵称、简介、头像路径、
  更新时间）+ RLS：读公开（任何人）、写仅本人；
- `public.trips` 表加 `is_public` 列（默认 `false`，已有行程不受影响）
  + `trips_select_public` 公开读策略（原 4 条仅本人策略不动）；
- 给 `storage.objects` 加 4 条 `public-files` 桶策略：写仅本人、
  读公开。

## 步骤 3：执行后核对（都在 SQL 编辑器里跑查询）

```sql
-- 1) profiles 表存在，且只有这 5 列
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'profiles'
ORDER BY ordinal_position;

-- 2) trips 表多了 is_public 列（boolean，默认 false）
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'trips'
  AND column_name = 'is_public';

-- 3) 策略都在（应看到 5 条新增：profiles 4 条 + trips 公开读 1 条，
--    以及 storage.objects 上的 4 条 public_files_*）
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE tablename IN ('profiles', 'trips')
ORDER BY tablename, policyname;
SELECT policyname FROM pg_policies
WHERE tablename = 'objects' AND policyname LIKE 'public_files_%';

-- 4) 桶存在：控制台 → 云存储 → Bucket 管理，列表里有 public-files。
```

以上 4 项都对，才算执行完成；有任何一项不对不要继续联调，
先把报错原文发回来。

## 步骤 4：联调（控制台执行完之后才能做）

1. 手机上打开 App → 个人页 → 编辑资料，改昵称/简介并保存；
   控制台 SQL 编辑器跑 `SELECT * FROM public.profiles;` 应看到
   该账号的一行（`user_id` 为云端账号 id，不是本机 `DT-xxxx`）。
2. 把一条行程设为公开，再点“上传到云端”；
   `SELECT id, owner, is_public, storage_path FROM public.trips;`
   应看到该行 `is_public = true`，且 `storage_path` 以
   `public-files/` 开头。
3. 另一台手机（或退出登录后的匿名账号）打开云端页 → 公开资料区，
   输入上面那个账号的云端用户 ID，能看到昵称/简介与公开行程，
   点行程能看到轨迹线；私有行程不出现。
4. 把同一条行程改回“仅自己可见”：`trips` 行的 `is_public` 应变回
   `false`，`storage_path` 变回不带 `public-files/` 前缀，
   `public-files` 桶里该行程的旧文件应已被删掉。

## 公开含义（执行前请确认）

- `profiles` 公开读意味着任何拿到环境 ID 的人都能读到全部用户的
  昵称、简介与头像路径；`trips` 公开读意味着任何拿到环境 ID 的人
  都能读到 `is_public = true` 的行程摘要与公开桶里的轨迹文件。
  这是公开资料的固有含义，不另加限制。
- 公开桶里只放公开文件：公开行程的轨迹文件与公开头像。私有行程
  仍走 `trip-files` 私有桶，App 代码按行程公开标记自动分桶，
  不会把私有文件放进公开桶。
- 收回公开 = 用户把行程改回仅自己可见，App 会把轨迹文件搬回
  私有桶并删掉公开桶里的旧文件；已下载到别人手机里的副本收不回。
