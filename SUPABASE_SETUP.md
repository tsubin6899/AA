# Supabase 設定

1. 開啟 Supabase 專案的 **SQL Editor**。
2. 複製執行 `supabase-schema.sql`。
3. 在 Authentication → Providers → Email 確認 Email 登入已啟用。
4. 部署網站後，按右上角「登入同步」即可使用 Email 與密碼登入。

## 邀請其他人加入

執行新版 `supabase-schema.sql` 後，登入管理者帳號，打開旅行並按「邀請成員」。系統會產生只對應這一趟旅行的邀請連結；對方開啟連結、登入自己的帳號，再輸入成員名稱，就會把這趟旅行加入自己的帳號。

這個版本採「安全匯入旅行副本」：不會讓成員看到管理者的其他旅行，也不會把所有資料公開。若未來需要多人即時共同編輯同一筆資料，再升級成共享旅行資料表即可。

目前前端會先保留本機資料；登入後會將資料同步到 `travel_workspaces`。publishable key 可以放在前端，請勿把 `service_role key` 放入網站。
