# winson3QQ/firmware(Batman 的 OpenMANET build 樹)— 給每個 session 的規則

**正本是 Batman repo 的 `docs/boards-and-builds.md`**(在這棵樹裡也看得到:`feeds/batman/docs/boards-and-builds.md`)。這裡只列規則。

- **分支 `build-3aplus` 同時 build 兩塊板**:`ekh-bcm2711`(Pi 4)和 `ekh-bcm2710`(Pi 3A+)。`build-108-batman` 凍結在 1.4.14,不要再用,也不要改。
- **唯一的 build 入口**:`scripts/build-board.sh <board> [--card]`。不要自己拼 `openmanet_setup.sh` 的參數,不要裸跑 `make defconfig`。
  - 配方在 `boards/<board>/batman-recipe`,CI 也讀同一份。
  - 產生的 `.config` 必須等於 `boards/<board>/batman-config.lock`。故意改配方或 feed pin 時:先跑 `build-board.sh <board> --update-lock`,review diff,再一起 commit。
- **`files/etc/batman-build` 由 `scripts/stamp-batman-build.sh` 在 build 時產生,不要手寫。** 只有 `batman-release.env`(版本號、channel、build 序號、features、note)是手改的。
  - feeds/batman 跟 `feeds.conf.default` 的 pin 不一致時,戳記腳本會拒絕;`build-board.sh` 會自動跑 `-i` 更新 feeds。
  - DIRTY build 只能拿來測試,不能 release。
- 改 feed pin(`feeds.conf.default`)= 換掉兩塊板的 Batman 程式:兩塊板都要重新 build、重新驗證。
- 這台開發機:WSL `wsl -d Ubuntu-24.04 -u yello`,樹在 `/home/yello/firmware-2710`。
  - `wsl bash -c '...'` 會吃掉 `$變數`,一律寫成腳本檔再執行。
  - 從 Windows 寫進這棵樹的檔案擁有者會變成 root,要 `chown yello`。
  - WSL 裡 `git push` 會卡在認證,改用 Windows git:`git -c safe.directory='*' -C //wsl.localhost/Ubuntu-24.04/home/yello/firmware-2710 push github <branch>`。
- 回覆使用繁體中文;動手前先給計畫;PR 附實測結果;PR 由使用者 merge。
