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

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

// Stored in Google Secret Manager — set with `firebase functions:secrets:set ...`
const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");
const ELEVENLABS_AGENT_ID = defineSecret("ELEVENLABS_AGENT_ID");
const ELEVENLABS_PHONE_NUMBER_ID = defineSecret("ELEVENLABS_PHONE_NUMBER_ID");
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const OUTBOUND_CALL_URL = "https://api.elevenlabs.io/v1/convai/twilio/outbound-call";

// Alias that auto-tracks the current Flash release, so this won't 404 when a
// specific version is retired. Pin to e.g. "gemini-3.5-flash" if you need stability.
const GEMINI_MODEL = "gemini-flash-latest";
// Don't re-run Gemini on every rapid auto-capture; refresh at most this often.
const ANALYSIS_THROTTLE_MS = 15000;

// The victim's on-screen countdown drives escalation now: when their confirmation
// window expires without an "I'm safe" tap, the app sets `escalate: true` on the
// session, and this places the agent call. (Client-owned timing — see the
// EscalationController in the iOS app.)
exports.placeEscalationCall = onDocumentUpdated(
  {
    document: "sessions/{sessionId}",
    secrets: [ELEVENLABS_API_KEY, ELEVENLABS_AGENT_ID, ELEVENLABS_PHONE_NUMBER_ID],
  },
  async (event) => {
    const before = event.data?.before?.data() || {};
    const after = event.data?.after?.data();
    if (!after) return;

    // Only act on the moment `escalate` flips true, and only once.
    if (after.escalate !== true || before.escalate === true) return;
    if (after.escalatedAt) return;
    if (!after.escalationPhone) return;

    await placeCall(event.params.sessionId, after);
  }
);

//
//  Emergency fan-out: when a new session is written, push a notification to
//  every friend in notifyIds so their phone rings even if the app is closed.
//
exports.notifyFriendsOnEmergency = onDocumentCreated("sessions/{sessionId}", async (event) => {
  const session = event.data?.data();
  if (!session) return;

  const notifyIds = Array.isArray(session.notifyIds) ? session.notifyIds : [];
  if (notifyIds.length === 0) return;

  const name = session.triggeredBy || "A friend";

  // Firestore's `in` query caps at 30 ids; chunk to stay within the limit.
  const tokens = [];
  for (let i = 0; i < notifyIds.length; i += 30) {
    const chunk = notifyIds.slice(i, i + 30);
    const snap = await db.collection("users").where("__name__", "in", chunk).get();
    snap.forEach((doc) => {
      const token = doc.get("fcmToken");
      if (typeof token === "string" && token.length > 0) tokens.push(token);
    });
  }

  if (tokens.length === 0) {
    logger.info("Emergency created but no friend tokens to notify", {
      sessionId: event.params.sessionId,
    });
    return;
  }

  const body = `${name} has triggered an emergency.`;
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: "Emergency Alert", body },
    apns: {
      payload: {
        aps: { sound: "default", "content-available": 1 },
      },
    },
    data: {
      sessionId: event.params.sessionId,
      triggeredBy: name,
    },
  });

  logger.info("Emergency push fan-out", {
    sessionId: event.params.sessionId,
    sent: res.successCount,
    failed: res.failureCount,
  });
});

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

    // Publish an "analyzing" status so the app can show a live spinner. We also
    // bump analysisUpdatedAt here so the throttle covers this in-flight run.
    await sessionRef.update({
      analysisStatus: "analyzing",
      analysisUpdatedAt: FieldValue.serverTimestamp(),
    });

    const fail = async (reason) => {
      await sessionRef.update({ analysisStatus: "failed", analysisError: String(reason).slice(0, 300) });
    };

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
        const msg = json?.error?.message || `HTTP ${res.status}`;
        logger.error(`Gemini analysis failed (${res.status}): ${msg}`, { sessionId, json });
        await fail(`${res.status}: ${msg}`);
        return;
      }

      const text = json.candidates?.[0]?.content?.parts?.[0]?.text;
      if (!text) {
        const reason = json.candidates?.[0]?.finishReason || "no content returned";
        logger.warn("Gemini returned no text", { sessionId, reason, promptFeedback: json.promptFeedback });
        await fail(`blocked or empty (${reason})`);
        return;
      }

      const parsed = parseGeminiJson(text);
      if (!parsed) {
        logger.error("Gemini JSON parse failed", { sessionId, text: text.slice(0, 800) });
        await fail("could not parse model response");
        return;
      }

      await sessionRef.update({
        analysis: { ...parsed, model: GEMINI_MODEL, capturesAnalyzed: parts.length - 1 },
        analysisStatus: "done",
        analysisError: FieldValue.delete(),
        analysisUpdatedAt: FieldValue.serverTimestamp(),
      });
      logger.info("Suspect analysis updated", { sessionId, present: parsed.present });
    } catch (err) {
      logger.error("Gemini analysis error", { sessionId, err: String(err) });
      await fail(err);
    }
  }
);

// Gemini sometimes wraps JSON in ```json fences or adds stray prose even when
// asked for raw JSON. Strip fences, then fall back to the first {...} block.
function parseGeminiJson(text) {
  const cleaned = text.trim().replace(/^```(?:json)?/i, "").replace(/```$/, "").trim();
  try {
    return JSON.parse(cleaned);
  } catch (_) {
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start !== -1 && end > start) {
      try {
        return JSON.parse(cleaned.slice(start, end + 1));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
