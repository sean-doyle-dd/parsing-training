# parsing-training (containerized)

A Docker Compose port of Datadog's `sandbox/vagrant/agent7/parsing-training` exercise —
sends deliberately unparsed logs to Datadog so you can practice building a
log processing pipeline (Grok Parser, Remappers, URL Parser, Arithmetic
Processor, Category Processor).

Original exercise ran everything inside a Vagrant-managed Ubuntu 18.04 VM.
This version skips the VM entirely — the original `setup.sh` mostly just
installed Docker *inside* the VM and then ran two `docker run` commands, so
if you already have Docker installed, the VM was never actually necessary.

## What changed: Vagrant → Docker

| Original (Vagrant) | This version | Why |
|---|---|---|
| `Vagrantfile` (`config.vm.box`, provisioners, synced folders) | Removed entirely | No VM — containers run directly on the host's Docker |
| `setup.sh`: `apt-get update`, install `curl`/`git`, `get.docker.com` install script | Removed | Bootstrapping a Linux box for Docker; unnecessary if Docker Desktop/Engine is already installed |
| `setup.sh`: `cp ~/data/bashrc.txt ~/.bashrc` | Removed | Cosmetic shell setup for a disposable VM shell, not relevant on the host |
| `setup.sh`: two manual `docker run ...` commands | `docker-compose.yml` | Same two containers, declared once instead of imperative shell commands |
| `sudo docker run -d --name datadog-agent -e DD_API_KEY=... datadog/agent:latest` (no `pid`/`cgroup` host mode) | `datadog-agent` service with `pid: host`, `cgroup: host` added | On a real Linux VM the Agent already shares the host kernel; when running on macOS/Windows via Docker Desktop, the Agent container needs these explicitly to see real process/cgroup data |
| `-e DD_AC_EXCLUDE="name:datadog-agent"` | `DD_CONTAINER_EXCLUDE_LOGS: "name:datadog-agent"` | `DD_AC_EXCLUDE` is the legacy variable name for the same idea. Also narrowed from excluding both metrics+logs to logs-only, so the Agent's own container metrics still show up in Infrastructure → Containers |
| `-v /opt/datadog-agent/run:/opt/datadog-agent/run:rw` (host bind mount) | Named volume `dd-agent-run` | A named volume doesn't require that exact path to already exist on the host |
| `random-logger/` (Dockerfile, entrypoint.sh, words.txt) | **Unchanged** | This is the actual training content — no reason to touch it |
| `sendlogs.sh` (curl straight to HTTP Log Intake, no Agent/Docker involved) | Left out of Compose on purpose | Separate exercise path entirely; run directly with `bash sendlogs.sh` if needed, no container required |

## Project structure

```
parsing-training/
├── docker-compose.yml     Datadog Agent + log generator, two services
├── .env.example           Copy to .env, set your DD_API_KEY
├── .gitignore
└── random-logger/
    ├── Dockerfile          FROM alpine:3.6
    ├── entrypoint.sh       Generates one messy log line every 1-5s
    └── words.txt           Word list used to build fake URLs/messages
```

## Setup

```bash
git clone git@github.com:<your-username>/parsing-training.git
cd parsing-training
cp .env.example .env
# edit .env and set your real DD_API_KEY
docker compose up --build -d
```

**Verify the log generator is producing lines:**
```bash
docker logs dog-logs --tail 10
```
Expect to see lines like:
```
[Mon, 14 Sep 2026 09:31:06 +0000] Some text here that isn't JSON. [Message Begins] {"key": "value", "another_key": "another_value", "measure_one": 54, "status": "INFO", "url": "https://testsite.com/unmeasurably?page=50#orthodontist"} [user9]
```

**Verify the Agent is shipping them:** in Datadog, **Logs → Live Tail**, filter
`source:myapp1`. This works automatically — the Agent tags container logs by
image name by default, and the image is explicitly tagged `myapp1` in the
compose file (`image: myapp1` under the `dog-logs` service) to match.

## Building the pipeline

All of this happens in the Datadog UI — nothing left to containerize once
logs are flowing.

**Logs → Pipelines → New Pipeline**, filter on `source:myapp1`, then add
these processors **in this exact order** (order matters — later processors
depend on fields the earlier ones create):

1. **Grok Parser.** Each rule goes in its own separate rule box (there's a
   drag handle and a "+ Add a new rule" link — don't put multiple rules on
   one line, the editor treats that as a single invalid rule):
   ```
   log_parser_rule \[%{_date}\] %{data:log_message} \[Message Begins\] %{data::json} \[%{_username}\]
   ```
   ```
   _username %{word:username}
   ```
   ```
   _date %{date("EEE, dd MMM yyyy HH:mm:ss Z"):log_date}
   ```

2. **Message Remapper** on `log_message` — then **disable it** once
   confirmed working (its job is done after the first successful run;
   leaving it on doesn't break anything, this just matches the original
   walkthrough).

3. **Status Remapper** on `status`.

4. **URL Parser** on `url` — set "URL attribute" to `url` (not the default
   `http.url` — nothing in this data is named that).

5. **Arithmetic Processor** — expression `measure_one * 900`, target
   attribute `measure_one` (overwrites in place) or a new name like
   `measure_one_scaled` if you want to keep the raw value too.

6. **Category Processor** — new attribute `category`:
   - `low_value` when the scaled value is `<=15000`
   - `high_value` when `>15000`
   
   Filter on whichever attribute name the arithmetic step actually wrote to.

**Don't forget:** saving an individual processor only stages it. Nothing
takes effect on real logs until you click **Apply Changes** at the bottom
of the pipeline editor.

## Verifying it worked

**Logs → Live Tail**, filter `source:myapp1`, click into an individual log.
The **Event Attributes** panel should show, as separate fields (not buried
in raw text):
- `log_message`, `username`, `log_date`
- `status` (colored correctly)
- `http.url_details.host` / `.path` / `.queryString.page` / `.scheme`
- `measure_one` (multiplied by 900 from the raw value)
- `category` (`low_value` or `high_value`)

## Troubleshooting notes from setting this up

- **Grok rule showing a red warning icon on `_date`/`_username`:** almost
  always means the main rule and helper rules got typed into the *same*
  text box instead of separate ones. Each rule needs its own box.
- **Changes not appearing to do anything after saving a processor:**
  Datadog's pipeline editor stages edits in a "Preview Changes" workflow.
  Look for a **Cancel Changes / Apply Changes** bar — usually bottom right
  of the editor — and click Apply Changes to actually commit.
- **Category Processor not categorizing anything:** check processor order.
  If the Category Processor runs *before* the Arithmetic Processor, it's
  evaluating against a field that doesn't exist yet. Drag it below the
  Arithmetic Processor using the row's drag handle.

## Cleanup

```bash
docker compose down
```
