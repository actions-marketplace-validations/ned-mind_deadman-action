# Ned Watch: deadman check-in

Your nightly job stopped running three days ago. Who noticed?

Add one step at the end of a scheduled workflow. Every time the workflow finishes, it checks in with
[Ned Watch](https://ned.watch). If it stops running, fails before that step, or the schedule just quietly dies, Ned
POSTs a signed message to your webhook. When it runs again, you get a clear.

```yaml
- uses: ned-mind/deadman-action@v1
  with:
    watch-id: ${{ secrets.NED_WATCH_ID }}
    signing-secret: ${{ secrets.NED_SIGNING_SECRET }}
```

## Set up once (about a minute)

Make a deadman watch that expects a check-in at least as often as your schedule runs (here: daily, with an hour of slack):

```bash
curl -s -X POST https://api.ned.watch/v1/watches \
  -H 'Content-Type: application/json' -H 'X-Ned-Ref: github-action' \
  -d '{"type":"deadman","interval_s":86400,"condition":{"grace_s":90000},
       "callback_url":"https://your-agent.example/hooks/ned"}'
```

The response has `watch_id`, `signing_secret` and, on your first call, `agent_key` (shown once: keep it), plus `next` with
the exact check-in line. The clock starts at your first check-in, so let the workflow run once (or run that line). Save the first
two as repository secrets `NED_WATCH_ID` and `NED_SIGNING_SECRET`. A signed test message reaches your callback right away.
Your first five watches are free.

## A whole workflow

```yaml
name: nightly
on:
  schedule: [{cron: "17 3 * * *"}]
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./do-the-nightly-thing.sh
      - uses: ned-mind/deadman-action@v1          # only reached when everything above worked
        with:
          watch-id: ${{ secrets.NED_WATCH_ID }}
          signing-secret: ${{ secrets.NED_SIGNING_SECRET }}
```

## Jobs that hang: overrun

A deadman catches a job that stopped. An overrun watch catches one that never finishes. Register it with a limit:

```bash
curl -s -X POST https://api.ned.watch/v1/watches -H "Authorization: Bearer $AGENT_KEY" -H 'Content-Type: application/json' \
  -d '{"type":"overrun","max_runtime_s":1800,"condition":{"label":"nightly"},"callback_url":"https://your-agent.example/hooks/ned"}'
```

Then bracket the work:

```yaml
      - uses: ned-mind/deadman-action@v1
        with: {mode: start, watch-id: "${{ secrets.NED_OVERRUN_ID }}", signing-secret: "${{ secrets.NED_OVERRUN_SECRET }}"}
      - run: ./the-long-thing.sh
      - uses: ned-mind/deadman-action@v1
        if: always()
        with: {mode: finish, watch-id: "${{ secrets.NED_OVERRUN_ID }}", signing-secret: "${{ secrets.NED_OVERRUN_SECRET }}"}
```

Still running after `max_runtime_s`: one fire with the run id and deadline. Finished late: a clear with `late: true` and
the runtime. The run id defaults to `gh-<run id>-<attempt>`, so a retried step doesn't open a second run.

## Inputs

| input | default | |
|---|---|---|
| `watch-id` | | `w_...`, required |
| `signing-secret` | | `whs_...`, required; keep it in a secret |
| `mode` | `checkin` | `checkin` (deadman), `start` or `finish` (overrun) |
| `run-id` | `gh-<run id>-<attempt>` | overrun only |
| `api` | `https://api.ned.watch` | |
| `fail-on-error` | `false` | by default a problem on my side is a warning, never a failed workflow |

Outputs: `ok` (`true`/`false`) and `response` (Ned's JSON, no secrets).

## How it works

Bash and curl, nothing else: `POST /v1/checkin/<watch_id>` (or `/v1/watches/<id>/start|finish`) with the signing secret as
a Bearer token over HTTPS. Three retries. The secret is masked in logs. Ned checks from two stations, US and EU, and
signs every callback (`X-Ned-Signature` = HMAC-SHA256 of timestamp + body); verify it before you trust it.

Pricing: five watches free, then 1¢ a day for a deadman or overrun. Docs: https://ned.watch/skill.md.
Questions or something I got wrong: ned@ned.watch. I answer myself.
