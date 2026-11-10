# DriveTrack 云端二期（腾讯 CloudBase PG 模式）控制台配置

环境：上海地域、PG 模式（PostgreSQL）。环境 ID 只存在本地
`.cloudbase-env` 文件里（600 权限，不进仓库），不要写进代码。

## 1. 建 trips 表 + RLS（SQL 编辑器一次跑完）

控制台 → 数据库 → SQL 编辑器，把 `trips-rls.sql` 全文粘贴执行。

它做的事：

- 建 `public.trips` 表（字段见文件头注释；PostgREST 自动把它
  暴露成 `https://<env>.api.tcloudbasegateway.com/v1/rdb/rest/trips`，
  App 的数据层就调这个地址）；
- 开行级安全（RLS），只放行 owner 本人读写（SELECT / INSERT /
  UPDATE / DELETE 四条策略，条件都是 `owner = auth.uid()`）；
- 给 `storage.objects` 加四条策略，只放行本人在 `trip-files`
  桶里以自己 user id 开头路径的对象（上传轨迹文件用）。

注意：新版本不再用匿名登录进入主界面。已经存在的匿名账号
仍要能绑定邮箱或手机号升级，所以 GRANT 与策略继续覆盖 `anon`
与 `authenticated`。匿名 JWT 的 role 是 `anon`，sub 是真实
user id。不要只开 authenticated，否则这些旧账号在升级前读不到
自己的云端行程。

另注意：RLS 是最终防线。App 查云端行程时固定带
`owner=eq.<当前 user id>`，与策略条件一致；即使查询不带
条件，RLS 也只会返回自己的行。

## 2. 建轨迹文件桶

控制台 → 云存储 → Bucket 管理 → 新建 Bucket，名字填
`trip-files`，权限选私有；MIME 白名单留空（默认不限；
App 上传的是 `application/json` 轨迹文件）。

桶不存在时上传会失败（App 里显示上传失败，可重试；行程不丢）。
传统模式的旧桶（文档库版的那个）不能复用——PG 模式的桶是
另一套 pgstore 桶，必须新建。

## 3. 开登录方式

控制台 → 身份认证 → 登录方式，开启：

- 用户名密码登录（邮箱密码登录用）；
- 邮箱验证码（注册与绑定邮箱发验证码用；选“开启邮件代发”
  即可，当前环境每分钟发送不得超过 10 封）；
- 短信验证码登录（仅上海地域，主登录方式）。先在腾讯云短信
  控制台申请签名和模板，审核通过后再填回 CloudBase。中国大陆
  与港澳台 / 国际要分别配置。号码按国际格式提交，例如
  `+86 13800000000`、`+852 …`。审核完成前，短信发不出去。

匿名登录可以继续开着，只给已经存在的匿名账号做绑定升级。
App 不会再新建匿名账号，也不会凭匿名会话进入记录界面。
邮箱密码和邮箱验证码仍可用，作为手机号之外的登录方式。

## 4. 云存储（App 侧已接好，不用再配）

轨迹 JSON 文件由 App 直接上传到 `trip-files` 桶，路径为
`<user id>/<trip id>.json`，上传走 PG Storage API
（POST `/v1/storages/object/trip-files/<路径>`，带
`x-upsert: true`，同路径重传会覆盖），权限由第 1 步的
`storage.objects` 策略控制，不公开列举。

## 5. 公开资料 + 公开行程（本轮新增）

执行步骤见 `cloudbase/profiles-public-steps.md`（按顺序做：
先建 `public-files` 公开桶，再执行 `profiles-public.sql`，
最后按文件里的查询核对）。

它做的事：

- 建 `public.profiles` 表（`user_id` 主键、昵称、简介、头像路径、
  更新时间）+ RLS：读公开（任何人）、写仅本人；
- `public.trips` 表加 `is_public` 列（默认 `false`，已有行程不受影响）
  + `trips_select_public` 公开读策略（原 4 条仅本人策略不动）；
- 给 `storage.objects` 加 4 条 `public-files` 桶策略：写仅本人、
  读公开。

App 侧分桶规则（代码见 `lib/cloud_service.dart`）：

- 公开行程：轨迹文件传 `public-files` 公开桶，`trips` 行写
  `is_public = true`，`storage_path` 为
  `public-files/<user id>/<trip id>.json`；
- 私有行程：轨迹文件传 `trip-files` 私有桶，`is_public = false`，
  `storage_path` 为 `<user id>/<trip id>.json`（不带前缀，与旧行兼容）；
- 公开头像：传 `public-files` 公开桶，路径
  `<user id>/avatar.jpg`（或 `.png`），`profiles` 行的
  `avatar_path` 存带 `public-files/` 前缀的完整路径；
- 已上传行程改公开标记后，App 会把轨迹文件重传到新标记对应的桶，
  再改 `trips` 行的 `is_public` 与 `storage_path`，改回私有后
  删掉公开桶里的旧文件。

公开含义：`profiles` 公开读意味着任何拿到环境 ID 的人都能读到
全部用户的昵称、简介与头像路径；`trips` 公开读意味着任何拿到
环境 ID 的人都能读到 `is_public = true` 的行程摘要与公开桶里的
轨迹文件。这是公开资料的固有含义，不另加限制。
