# Fudan Canvas token refresh wrapper

This directory includes a wrapper for the existing `canvas-downloader` binary.
It can validate `canvas-downloader.toml` before each sync, or force-create a new
Canvas access token every time. When a new token is created, the wrapper updates
only the `canvas_token` line and then runs the original downloader.

## Configure credentials

Preferred Docker Compose secrets:

```text
secrets/fudan_username
secrets/fudan_password
```

Each file should contain only the secret value. The compose file mounts them as:

```text
/run/secrets/fudan_username
/run/secrets/fudan_password
```

Environment variables are also supported:

```text
FUDAN_USERNAME=...
FUDAN_PASSWORD=...
```

## Run once

The default Compose command refreshes the token, sets it to expire one day from
the current NAS local time, and resolves the term whose name is
`2026-2027学年第一学期`. It never falls back to a stale numeric term. On the NAS,
`/downloads` is mounted from `/vol3/1000/kniplab/26-27秋学期`:

```yaml
command: ["--force-refresh-token", "--token-expires-after-days", "1", "--", "-n", "-d", "/downloads"]
```

Then run:

```bash
docker compose run --rm fudan-canvasdownloader
```

If this is the first run on the NAS, or the image has not been built yet, build
it once first:

```bash
docker compose build
```

## Schedule on FnOS/NAS

The default Compose command already performs the required sequence:

1. force-create a new Canvas access token;
2. validate it and write it into `canvas-downloader.toml`;
3. query the account's active courses and find the uniquely named target term;
4. write `.state/2026-fall-courses.json` without credentials;
5. inject the discovered Term ID and run `canvas-downloader -n -d /downloads`.

If the target term is not published yet, the job logs a normal `pending` state,
returns success, and downloads nothing. If multiple IDs have the same term
name, the job fails safely instead of choosing one.

To install the NAS command-line schedule for 07:00 and 19:00 every day, run this
on the NAS:

```bash
cd /vol1/1000/Docker/Fudan_canvasdownloader
sh install-nas-cron.sh
```

Verify the installed cron entry:

```bash
crontab -l
```

The installed cron entry calls `run-nas-cron-sync.sh`, which writes wrapper logs
to `sync-cron.log` and prevents overlapping runs when `flock` is available.
Failures are retried up to three attempts with a 60-second delay; `pending`
returns success and is not retried. Override with `CANVAS_RUN_RETRIES` and
`CANVAS_RETRY_DELAY_SECONDS` if needed.

If this directory is mounted elsewhere on the NAS, pass the actual project path:

```bash
sh install-nas-cron.sh /actual/path/to/Fudan_canvasdownloader
```

## Per-run update logs

After each downloader run, the wrapper writes a Markdown file to `log/`. The file
name uses the sync start time, for example:

```text
log/2026-05-23_07-00-25.md
```

Each file records the sync start time, finish time, exit code, download
directory, and the files that were added, modified, or deleted during that run.
The wrapper detects changes by comparing file size and modified time before and
after `canvas-downloader` runs.

The log directory can be changed with:

```bash
python refresh_and_run.py --update-log-dir custom-log \
  --target-term-name '2026-2027学年第一学期' -- -n -d /downloads
```

Or with the environment variable:

```text
CANVAS_UPDATE_LOG_DIR=custom-log
```

## Token refresh options

Force token refresh before every downloader run:

```bash
python refresh_and_run.py --force-refresh-token --token-expires-after-days 1 \
  --target-term-name '2026-2027学年第一学期' \
  --course-manifest .state/2026-fall-courses.json -- -n -d /downloads
```

`--token-expires-at` or `CANVAS_TOKEN_EXPIRES_AT` can still be used for a fixed
expiration timestamp. A fixed timestamp takes precedence over
`--token-expires-after-days`.

## Notes

- Logs go to `sync.log` and Docker stdout. Token-like values are redacted.
- The checked-in Rust CLI requires camelCase JSON credentials with `-c`.
  The wrapper converts its refreshed TOML configuration to a temporary `0600`
  JSON file inside a private directory, passes only its path, and removes it
  when the downloader exits. Explicit credential-file overrides are rejected.
- Per-run file update logs go to `log/*.md` by default.
- Browser session state is stored in `.state/playwright-storage.json`.
- The course manifest contains only term/course metadata and teacher names; it
  never contains passwords, cookies, or access tokens.
- `canvas-downloader.toml`, browser state, logs, and Docker secrets are ignored
  by Git and written with owner-only permissions where applicable.
- If Fudan SSO asks for captcha, QR scan, SMS, or app approval, the wrapper stops
  and keeps the existing token config unchanged.
- The API token creation path is tried first. The settings-page UI path is only
  used as a fallback.
