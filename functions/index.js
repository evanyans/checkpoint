//
//  Checkpoint auto-escalation agent
//
//  Once per minute, this finds any emergency session that is still "triggered",
//  has an auto-call number configured, and has been live past its delay — then
//  places an outbound ElevenLabs conversational call (over Twilio) that tells the
//  contact who is in danger and where, and can answer their questions.
//
//  The timer lives here (not on the phone) on purpose: the escalation still fires
//  even if the phone is taken, killed, or offline.
//

const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");

initializeApp();
const db = getFirestore();

// Stored in Google Secret Manager — set with `firebase functions:secrets:set ...`
const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");
const ELEVENLABS_AGENT_ID = defineSecret("ELEVENLABS_AGENT_ID");
const ELEVENLABS_PHONE_NUMBER_ID = defineSecret("ELEVENLABS_PHONE_NUMBER_ID");
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const OUTBOUND_CALL_URL = "https://api.elevenlabs.io/v1/convai/twilio/outbound-call";

const GEMINI_MODEL = "gemini-2.5-flash";
// Don't re-run Gemini on every rapid auto-capture; refresh at most this often.
const ANALYSIS_THROTTLE_MS = 15000;

exports.escalateOverdueSessions = onSchedule(
  {
    schedule: "every 1 minutes",
    secrets: [ELEVENLABS_API_KEY, ELEVENLABS_AGENT_ID, ELEVENLABS_PHONE_NUMBER_ID],
  },
  async () => {
    // Single-field query — no composite index needed. Few sessions are ever live.
    const snap = await db.collection("sessions").where("status", "==", "triggered").get();
    const now = Date.now();

    const pending = [];
    snap.forEach((doc) => {
      const s = doc.data();
      if (!s.escalationPhone) return; // auto-call not configured for this session
      if (s.escalatedAt) return; // already handled
      const createdAt = s.createdAt?.toMillis?.();
      if (!createdAt) return; // serverTimestamp not resolved yet — catch it next minute
      const delayMs = (s.escalationDelayMinutes ?? 5) * 60 * 1000;
      if (now < createdAt + delayMs) return; // not overdue yet
      pending.push(placeCall(doc.id, s));
    });

    if (pending.length) {
      logger.info(`Escalating ${pending.length} overdue session(s).`);
      await Promise.allSettled(pending);
    }
  }
);

async function placeCall(sessionId, s) {
  const ref = db.collection("sessions").doc(sessionId);

  // Claim the session in a transaction so two overlapping runs can't double-call.
  const claimed = await db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    if (!fresh.exists || fresh.get("escalatedAt") || fresh.get("status") !== "triggered") {
      return false;
    }
    tx.update(ref, {
      escalatedAt: FieldValue.serverTimestamp(),
      escalationStatus: "calling",
    });
    return true;
  });
  if (!claimed) return;

  const hasLoc = typeof s.latitude === "number" && typeof s.longitude === "number";
  const location = hasLoc
    ? `latitude ${s.latitude.toFixed(4)}, longitude ${s.longitude.toFixed(4)}`
    : "an unknown location";
  const mapsLink = hasLoc ? `https://maps.google.com/?q=${s.latitude},${s.longitude}` : "";

  // Fold the AI evidence analysis into the call so the agent can describe the suspect.
  const suspect = s.analysis?.present && s.analysis?.summary
    ? s.analysis.summary
    : "no suspect has been identified in the footage yet";

  const body = {
    agent_id: ELEVENLABS_AGENT_ID.value(),
    agent_phone_number_id: ELEVENLABS_PHONE_NUMBER_ID.value(),
    to_number: s.escalationPhone,
    // These fill the {{placeholders}} in the agent's prompt + first message.
    conversation_initiation_client_data: {
      dynamic_variables: {
        user_name: s.triggeredBy ?? "someone",
        minutes: String(s.escalationDelayMinutes ?? 5),
        location,
        maps_link: mapsLink,
        suspect_description: suspect,
      },
    },
  };

  try {
    const res = await fetch(OUTBOUND_CALL_URL, {
      method: "POST",
      headers: {
        "xi-api-key": ELEVENLABS_API_KEY.value(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    const json = await res.json().catch(() => ({}));

    if (!res.ok) {
      logger.error("ElevenLabs outbound call failed", { sessionId, status: res.status, json });
      await ref.update({
        escalationStatus: "failed",
        escalationError: JSON.stringify(json).slice(0, 500),
      });
      return;
    }

    logger.info("Escalation call placed", { sessionId, response: json });
    await ref.update({
      escalationStatus: "called",
      escalationCallSid: json.callSid ?? json.call_sid ?? null,
      escalationConversationId: json.conversationId ?? json.conversation_id ?? null,
    });
  } catch (err) {
    logger.error("Escalation call error", { sessionId, err: String(err) });
    await ref.update({
      escalationStatus: "error",
      escalationError: String(err).slice(0, 500),
    });
  }
}

// ---------------------------------------------------------------------------
// AI evidence analysis: describe the suspect from auto-captured stills (Gemini)
// ---------------------------------------------------------------------------

const SUSPECT_PROMPT = `You are an evidence-analysis assistant for a personal-safety app. The attached JPEG stills were auto-captured by a victim's phone during an ACTIVE emergency. Another person in frame may be an aggressor. Produce a factual, observational description to help responders recognize that person.

Strict rules:
- Describe ONLY what is clearly visible in the images.
- If an attribute is not visible or you are unsure, use null — do not guess.
- You may note plainly visible physical appearance (approximate skin tone, hair, build, clothing). Do NOT guess ethnicity, nationality, name, or identity.
- Never invent details. It is better to say null than to be wrong.
- If the only person visible appears to be the phone's owner (a single selfie-style face) or no other person is present, set "present" to false.

Return ONLY a JSON object with exactly this shape:
{
  "present": boolean,
  "summary": string,                    // 1-2 sentences a dispatcher could read aloud
  "sex": string|null,                   // apparent, e.g. "male-presenting"
  "ageRange": string|null,              // e.g. "20s-30s"
  "build": string|null,
  "height": string|null,
  "hair": string|null,
  "facialHair": string|null,
  "clothing": string|null,              // tops, bottoms, colors
  "accessories": string|null,           // hat, glasses, bag, mask
  "distinguishingFeatures": string[],   // tattoos, scars, logos; [] if none
  "confidence": "low"|"medium"|"high",
  "caveats": string|null                // what limits the description (blur, lighting, angle)
}`;

exports.analyzeSuspectFromCaptures = onDocumentCreated(
  {
    document: "sessions/{sessionId}/captures/{captureId}",
    secrets: [GEMINI_API_KEY],
  },
  async (event) => {
    const sessionId = event.params.sessionId;
    const sessionRef = db.collection("sessions").doc(sessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) return;

    // Throttle: auto-capture can fire rapidly; don't call Gemini on every frame.
    const lastMs = sessionSnap.get("analysisUpdatedAt")?.toMillis?.() ?? 0;
    if (Date.now() - lastMs < ANALYSIS_THROTTLE_MS) return;

    // Analyze the most recent few stills together for the best composite description.
    const capsSnap = await sessionRef
      .collection("captures")
      .orderBy("createdAt", "desc")
      .limit(4)
      .get();

    const parts = [{ text: SUSPECT_PROMPT }];
    capsSnap.forEach((d) => {
      const b64 = d.get("image");
      if (b64) parts.push({ inline_data: { mime_type: "image/jpeg", data: b64 } });
    });
    if (parts.length === 1) return; // no usable images

    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY.value()}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            contents: [{ parts }],
            generationConfig: { responseMimeType: "application/json", temperature: 0.2 },
          }),
        }
      );
      const json = await res.json();
      if (!res.ok) {
        logger.error("Gemini analysis failed", { sessionId, status: res.status, json });
        return;
      }

      const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) {
        logger.warn("Gemini returned no text", { sessionId });
        return;
      }

      let parsed;
      try {
        parsed = JSON.parse(text);
      } catch (e) {
        logger.error("Gemini JSON parse failed", { sessionId, text: text.slice(0, 500) });
        return;
      }

      await sessionRef.update({
        analysis: { ...parsed, model: GEMINI_MODEL, capturesAnalyzed: parts.length - 1 },
        analysisUpdatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("Suspect analysis updated", { sessionId, present: parsed.present });
    } catch (err) {
      logger.error("Gemini analysis error", { sessionId, err: String(err) });
    }
  }
);
