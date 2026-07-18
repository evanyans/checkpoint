# AI Evidence Analysis — Setup (Gemini)

When Checkpoint auto-captures evidence stills during an emergency, a Firebase Cloud Function
sends them to **Google Gemini** (vision) and writes a structured **suspect description** back
onto the session. It shows up in the **Log**, live during the emergency, and is passed into
the **escalation call agent's** context so the agent can describe the suspect.

```
Auto-captured stills (sessions/{id}/captures)
        │  onDocumentCreated trigger (throttled ~15s)
        ▼
  Gemini 2.5 Flash (vision)  →  { present, summary, build, clothing, features… }
        │
        ▼
  session.analysis  ──▶ Log detail view
                    ──▶ live "sparkles" summary in the emergency screen
                    ──▶ suspect_description dynamic var on the ElevenLabs call
```

The `analyzeSuspectFromCaptures` function is already in `functions/index.js`. You only need a
free Gemini API key.

---

## 1. Get a free Gemini API key

1. Go to **Google AI Studio** → <https://aistudio.google.com/apikey>
2. **Create API key** (a Google account is all you need — no billing).
3. Copy the key.

The free tier covers the Flash models with generous daily limits — fine for a demo.

## 2. Store it as a Firebase secret

From the repo root:

```bash
firebase functions:secrets:set GEMINI_API_KEY
```

Paste the key when prompted.

## 3. Deploy

```bash
firebase deploy --only functions
```

This deploys/updates both functions (`escalateOverdueSessions` and
`analyzeSuspectFromCaptures`). Requires the Blaze plan (same as the call feature).

---

## 4. Test

1. Trigger an emergency in the app so the camera starts and stills get captured
   (the face-capture pipeline saves them automatically; the viewer can also tap the
   shutter button to add stills).
2. Within a few seconds, open that incident in the **Log** tab — you should see an
   **"AI suspect description"** card. It also appears as a one-line summary live on the
   emergency screen.
3. Check the logs if nothing shows:

```bash
firebase functions:log --only analyzeSuspectFromCaptures
```

The function logs the Gemini HTTP status and any parse failures.

### Notes & tuning

- **Model**: `gemini-flash-latest` (see `GEMINI_MODEL` in `index.js`) — an alias that
  auto-tracks the current Flash release so it won't 404 when a version retires. Pin to a
  specific version like `gemini-3.5-flash` if you need stable behavior.
- **Throttle**: `ANALYSIS_THROTTLE_MS` (default 15s) caps how often Gemini is called as new
  stills stream in. Lower it for a snappier demo, raise it to save quota.
- **What it analyzes**: the most recent 4 stills together, for a composite description.
- **Safety framing**: the prompt tells Gemini to describe only what's visible, use null when
  unsure, and never guess identity/ethnicity. The UI labels it "a lead, not a positive ID."
- **Cost/keys**: the Gemini key lives only in Secret Manager, server-side. The app never
  sees it — it just reads the resulting `analysis` field from Firestore.

---

## How it connects to the call feature

`escalateOverdueSessions` reads `session.analysis.summary` and passes it as the
`suspect_description` dynamic variable. To use it, add `{{suspect_description}}` to your
ElevenLabs agent prompt, e.g.:

> "If asked what the person looks like, describe them: {{suspect_description}}."
