# Leadvyne SaaS — multi-tenant setup

Onboard clients from a front-end → one shared bot workflow serves all of them, routed by
Chatwoot inbox id. No per-client workflow, no per-client deploy.

```
leadvyne-onboarding.html  → POST → n8n/onboard.json  → writes a row to the CLIENTS table
                                                          │
Chatwoot (any client) ── webhook ──► n8n/bot-common.json ─┤ looks up tenant by inbox id
                                                          │ runs intent + flow + reply (text/voice/image)
                                                          └ reads/writes that tenant's leads table
n8n/followup-template.json → clone per client for scheduled nudges
```

## 1. Create the CLIENTS config table (NocoDB)

This is your **control plane** — one table holding every client's config. Read by all three
workflows using your **master** NocoDB token (the only fixed credential).

| Field | Type | Notes |
|---|---|---|
| client_name | Single line | |
| chatwoot_account_id | Single line | **routing** |
| chatwoot_inbox_id | Single line | **routing key — must be unique per client** |
| chatwoot_base | Single line | e.g. https://app.aiingo.com |
| chatwoot_token | Single line | that client's Chatwoot API token |
| nocodb_base | Single line | where the client's leads live |
| leads_table_id | Single line | the client's leads table id |
| nocodb_token | Single line | token for the client's leads table |
| openrouter_key | Single line | (can be a shared key) |
| model | Single line | google/gemini-2.5-flash |
| language | Single line | ml / en / hi / ta / mix |
| main_prompt | Long text | the FAQ agent persona + guardrails |
| flow_json | Long text | the state machine (JSON string) |
| followup_count | Number | |
| followup_hours | Single line | "24,72,168" |
| followup_messages | Long text | one per line |
| active | Single line | "Yes" / "No" |

Note the workspace id, project id, and table id — you'll paste them into the workflows.

## 2. Import the workflows

In each, set the three `REPLACE_CONTROL_*` placeholders to your CLIENTS table location, and
make sure the **master** NocoDB credential is selected on the nodes that read it.

- **onboard.json** — webhook `/webhook/leadvyne-onboard`. CORS is open (`*`) so the page can post.
- **bot-common.json** — webhook `/webhook/leadvyne-bot`. This is the URL every client pastes.
- **followup-template.json** — clone per client (follow-ups are low volume; per-client is fine here).

## 3. The key design: why one workflow works for all

n8n **credentials can't be chosen from a database field**. So `bot-common.json` does NOT use
NocoDB/credential nodes for client calls. It uses plain **HTTP Request** nodes and injects the
tenant's token into the header from the config row, e.g.:

- Chatwoot → `api_access_token: {{ $json.chatwoot_token }}`
- NocoDB (leads) → `xc-token: {{ $json.nocodb_token }}`
- OpenRouter → `Authorization: Bearer {{ $json.openrouter_key }}`

The single fixed credential is the master NocoDB token on **Get tenant**, which reads the
CLIENTS table. That's the whole trick that makes it multi-tenant.

## 4. Onboard a client (the front-end)

Open `leadvyne-onboarding.html`. Fill in basics, credentials, the main prompt, the flow
(there's a *Load sample flow* button), and the follow-ups. Hit **Provision client**. It writes
the config row and shows the one webhook URL.

In that client's Chatwoot inbox → **Configuration → Webhooks** → add `…/webhook/leadvyne-bot`
and subscribe to **Message created**. Done — routing is by inbox id, same URL for everyone.

> Host the HTML anywhere (Coolify static, or open locally). It posts to the onboard webhook,
> so the NocoDB token is never exposed in the browser.

## 5. Media: text / voice / image

- **Text** — straight through.
- **Image** — sent to Gemini vision via the attachment URL; the description becomes the message.
- **Voice** — downloaded, then transcribed by Gemini. WhatsApp voice is ogg/opus. If your model
  or endpoint rejects the audio, swap the **HTTP · Transcribe** node for your STT of choice
  (Whisper, Google STT). It falls back to a placeholder so the conversation never stalls.

## Tuning notes (be aware)
- `bot-common.json` is a working foundation. Test each branch once in n8n and adjust expressions
  for your exact Chatwoot payload (attachment field names vary slightly by channel).
- Inbox ids must be unique across clients in the CLIENTS table, or routing is ambiguous.
- For follow-ups beyond WhatsApp's 24-hour window, the send must be an approved **template**,
  not free text — see the sticky note in `followup-template.json`.
- This is the n8n-runtime version. The code-engine version (separate repo) is the alternative
  runtime; both read the same kind of per-client config.
