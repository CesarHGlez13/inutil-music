const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

const db = admin.firestore();

/**
 * Tarea periódica: desactiva automáticamente cuentas vencidas.
 * Se ejecuta una vez al día.
 */
exports.checkAccountExpirations = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async (context) => {
    const now = new Date();
    const snapshot = await db
      .collection("users")
      .where("isActive", "==", true)
      .where("role", "==", "user")
      .where("accountExpiresAt", "<", now.toISOString())
      .get();

    if (snapshot.empty) {
      console.log("No hay cuentas vencidas.");
      return null;
    }

    const batch = db.batch();
    snapshot.forEach((doc) => {
      console.log(`Desactivando cuenta vencida: ${doc.id}`);
      batch.update(doc.ref, {
        isActive: false,
        status: "expired",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await batch.commit();
    console.log(`Se actualizaron ${snapshot.size} cuentas a estado vencido.`);
    return null;
  });

/**
 * Cloud Function para que un administrador renueve o extienda los días de suscripción.
 */
exports.adminExtendAccountSubscription = functions.https.onCall(
  async (data, context) => {
    // Verificar que quien llama sea administrador
    if (!context.auth || !context.auth.token.admin) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Solo administradores pueden extender suscripciones."
      );
    }

    const { targetUid, additionalDays } = data;
    if (!targetUid || !additionalDays || additionalDays <= 0) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "UID de usuario y días válidos requeridos."
      );
    }

    const userRef = db.collection("users").doc(targetUid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new functions.https.HttpsError("not-found", "Usuario no encontrado.");
    }

    const currentData = userDoc.data();
    let currentExpiresAt = currentData.accountExpiresAt
      ? new Date(currentData.accountExpiresAt)
      : new Date();

    if (currentExpiresAt < new Date()) {
      currentExpiresAt = new Date();
    }

    const newExpiresAt = new Date(
      currentExpiresAt.getTime() + additionalDays * 24 * 60 * 60 * 1000
    );

    await userRef.update({
      accountExpiresAt: newExpiresAt.toISOString(),
      isActive: true,
      status: "active",
      accountDurationDays: additionalDays,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      userId: targetUid,
      newExpiresAt: newExpiresAt.toISOString(),
    };
  }
);
