# Auto-Escalation Call — Setup Guide

When an emergency in Checkpoint stays **unresolved past your chosen delay**, a Firebase
Cloud Function places an **outbound phone call** to a number you set in Settings. The call
is answered by an **ElevenLabs conversational AI agent** (spoken over a Twilio phone number)
that says who's in danger and where, and can answer the person's questions.

The timer runs **on the server**, so the call still fires even if the in-danger phone is
taken, killed, or offline.

```
Trigger emergency ──▶ Firestore session (status: "triggered", escalationPhone, delay)
                                   │
              every 1 min, Firebase Cloud Function checks:
              still triggered?  +  past the delay?  +  not already called?
                                   │ yes
                                   ▼
        POST api.elevenlabs.io/v1/convai/twilio/outbound-call
                                   │
              ElevenLabs agent calls your number over Twilio and talks
```

You'll set up three accounts — **Twilio** (the phone line), **ElevenLabs** (the voice/agent),
and **Firebase Blaze** (to run the function) — then deploy. Budget ~30 minutes.

---

## Part 1 — Twilio (the phone line)

Twilio is just the "dumb pipe" that carries the call; ElevenLabs does the talking.

1. Sign up at <https://www.twilio.com/try-twilio> (free trial includes credit).
2. In the Twilio Console, **buy a phone number** with *Voice* capability:
   **Phone Numbers → Manage → Buy a number** → pick one → Buy (~$1–2/mo, covered by trial credit).
3. From the Console **dashboard**, copy and keep handy:
   - **Account SID** (starts with `AC…`)
   - **Auth Token** (click to reveal)
   - Your new **phone number** in E.164 format, e.g. `+14155550123`

> Trial accounts can only call **verified** numbers. Add the number you'll test with
> under **Phone Numbers → Verified Caller IDs** (or upgrade to remove the limit).

---

## Part 2 — ElevenLabs (the agent + voice)

### 2a. Create the agent

1. Sign up at <https://elevenlabs.io> and open **Agents** (a.k.a. Conversational AI).
2. **Create a new agent.** Pick a voice you like.
3. Set the agent's **System prompt** (paste this — the `{{...}}` are filled in per call):

   ```
   You are Checkpoint, an automated emergency-escalation assistant making an urgent
   phone call. You are calling because {{user_name}} triggered an emergency in the
   Checkpoint personal-safety app and has NOT marked themselves safe after
   {{minutes}} minutes.

   Your goals, in order:
   1. Calmly and clearly tell the person who answers that {{user_name}} may be in danger.
   2. Give the last known location: {{location}}. If asked, a map link is {{maps_link}}.
   3. Urge them to try to reach {{user_name}} right now, and to call 911 (or local
      emergency services) if they cannot confirm {{user_name}} is safe.
   4. If asked who might be involved, share the AI description of the person seen in
      the footage: {{suspect_description}}. Present it as an unconfirmed lead from
      automated analysis, not a certain identification.
   5. Answer questions using ONLY the information above. If you don't know, say so.

   Be brief, serious, and calm. Do not hang up until they clearly acknowledge. If you
   reach voicemail, leave the same core message.
   ```

4. Set the agent's **First message**:

   ```
   Hello, this is an automated emergency call from Checkpoint. {{user_name}} may be in
   danger and hasn't checked in for {{minutes}} minutes. Their last known location is
   {{location}}. Please try to reach them right away, and call 911 if you can't confirm
   they're safe.
   ```

5. **Register the dynamic variables** so the agent accepts them. In the agent's settings
   find **Dynamic variables** (under Security/Advanced depending on UI) and add, with any
   placeholder defaults:
   `user_name`, `minutes`, `location`, `maps_link`, `suspect_description`
6. **Save**, then copy the **Agent ID** (in the agent's URL or its settings header).

### 2b. Connect your Twilio number to ElevenLabs

1. In ElevenLabs, go to **Agents → Phone Numbers → Import / Add number**.
2. Choose **Twilio**, then enter:
   - **Label**: e.g. `Checkpoint line`
   - **Phone number**: your Twilio number in E.164 (`+1…`)
   - **Twilio Account SID** and **Twilio Auth Token** from Part 1
3. Save. **Assign** the agent from Part 2a to this number.
4. Copy the **Phone Number ID** — this is your `agent_phone_number_id`
   (visible in the phone number's detail page/URL, or via
   `GET https://api.elevenlabs.io/v1/convai/phone-numbers` with your API key).

### 2c. Get your API key

- ElevenLabs → **profile menu → API Keys → Create key**. Copy it (starts with `sk_…` /
  `xi-…`). This is `ELEVENLABS_API_KEY`.

At the end of Part 2 you should have **three values**:

| Value | Env var | Looks like |
|---|---|---|
| API key | `ELEVENLABS_API_KEY` | `sk_...` |
| Agent ID | `ELEVENLABS_AGENT_ID` | `agent_...` |
| Phone Number ID | `ELEVENLABS_PHONE_NUMBER_ID` | `phnum_...` / a short id |

---

## Part 3 — Firebase (run the function)

### 3a. Upgrade to Blaze

Cloud Functions + Cloud Scheduler require the **Blaze (pay-as-you-go)** plan. It asks for a
card but has a generous free tier — a demo costs effectively nothing.
Console → your project **checkpoint-65b0d** → ⚙️ → **Usage and billing → Modify plan → Blaze**.

### 3b. Install tooling & log in

```bash
npm install -g firebase-tools     # if not already installed
firebase login
cd checkpoint                     # repo root (already has firebase.json + .firebaserc)
cd functions && npm install && cd ..
```

### 3c. Store the three secrets

```bash
firebase functions:secrets:set ELEVENLABS_API_KEY
firebase functions:secrets:set ELEVENLABS_AGENT_ID
firebase functions:secrets:set ELEVENLABS_PHONE_NUMBER_ID
```

Each command prompts you to paste the value. (Agent ID / Phone Number ID aren't strictly
secret, but storing them the same way keeps the code simple.)

### 3d. Deploy

```bash
firebase deploy --only functions
```

First deploy auto-enables the Cloud Scheduler + Pub/Sub APIs. You should see
`escalateOverdueSessions` deployed and scheduled `every 1 minutes`.

---

## Part 4 — Test it end-to-end

1. In the app, open **Settings → Automatic escalation call**:
   - **Auto-call number**: the phone you'll answer, in E.164 (and *verified* in Twilio if
     you're on a trial).
   - **After**: set to **1 min** for testing.
2. On the Home tab, **Trigger Emergency**. Leave it running (don't end it).
3. Within ~1–2 minutes your phone rings and the agent speaks. Answer and try asking
   "where are they?" — it should read back the location.
4. **End Emergency** in the app to resolve it. (Resolving *before* the delay cancels the
   call — that's the point.)

### If the call doesn't come

```bash
firebase functions:log --only escalateOverdueSessions
```

Check the session document in Firestore — the function writes back:

- `escalationStatus`: `calling` → `called` (success) or `failed` / `error`
- `escalationError`: the ElevenLabs API response when something went wrong

Common causes:
- **Trial number restriction** — the destination isn't verified in Twilio.
- **Wrong `agent_phone_number_id`** — must be the ElevenLabs phone-number id, not the raw number.
- **`createdAt` still pending** — the very first minute after triggering; it fires the next tick.
- **Number not E.164** — must start with `+` and country code.

---

## Cost & safety notes

- **Free tiers**: Twilio trial credit + ElevenLabs free agent minutes + Firebase Blaze free
  tier comfortably cover a demo. Watch ElevenLabs' monthly conversational-minute limit.
- **Keys never ship in the app.** They live only in Firebase Secret Manager and are read
  server-side. The iOS app only writes the *destination number* onto the session.
- **This is not a substitute for 911.** It's an escalation aid that nudges a human contact.

---

## How the pieces map to the code

- `functions/index.js` → `escalateOverdueSessions` (the scheduled check + the ElevenLabs call).
- iOS `SessionManager.createSession(...)` writes `escalationPhone` + `escalationDelayMinutes`.
- iOS `SettingsView` → the "Automatic escalation call" section (number + delay, stored via
  `@AppStorage`, read in `ContentView.triggerEmergency`).
- The agent reads `user_name` / `location` from the session's existing `triggeredBy` /
  `latitude` / `longitude` fields — no extra app changes needed.
