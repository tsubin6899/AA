# Supabase 設定

1. 開啟 Supabase 專案的 **SQL Editor**。
2. 複製執行 `supabase-schema.sql`。
3. 在 Authentication → Providers → Email 確認 Email 登入已啟用。
4. 部署網站後，按右上角「登入同步」即可使用 Email 與密碼登入。

目前前端會先保留本機資料；登入後會將資料同步到 `travel_workspaces`。publishable key 可以放在前端，請勿把 `service_role key` 放入網站。
