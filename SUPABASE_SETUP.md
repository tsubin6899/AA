# Supabase 設定

1. 開啟 Supabase 專案的 **SQL Editor**。
2. 複製執行 `supabase-schema.sql`。
3. 在 Authentication → Providers → Email 確認 Email 登入已啟用。
4. 部署網站後，按右上角「登入同步」即可使用 Email 與密碼登入。

## 邀請其他人加入

執行新版 `supabase-schema.sql` 後，登入管理者帳號，先在「旅行成員」建立朋友的名稱，再按「邀請成員」。選擇對應名稱並產生連結，傳給朋友。朋友開啟連結、登入自己的帳號後，就會加入同一趟共享旅行。

共享旅行在雲端只保存一份資料。受邀朋友只能讀取被邀請的旅行；任何一方新增或修改支出，另一方會收到同步更新。

目前前端會先保留本機資料；登入後會將資料同步到 `travel_workspaces`。publishable key 可以放在前端，請勿把 `service_role key` 放入網站。

新版也會建立 `travel_shared_trips`、成員權限和共享邀請資料表。請將完整新版 `supabase-schema.sql` 在 SQL Editor 再執行一次；其中的 `if not exists` 與更新政策指令會保留既有資料。
