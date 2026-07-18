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

const OUTBOUND_CALL_URL = "https://api.elevenlabs.io/v1/convai/twilio/outbound-call";

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
