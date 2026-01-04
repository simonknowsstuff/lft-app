const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { VertexAI } = require("@google-cloud/vertexai");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const project = process.env.GCLOUD_PROJECT;
const vertexAI = new VertexAI({ project: project, location: "us-central1" });

function getDistance(lat1, lon1, lat2, lon2) {
    const R = 6371e3;
    const rad = (deg) => deg * (Math.PI / 180);
    const dLat = rad(lat2 - lat1);
    const dLon = rad(lon2 - lon1);
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(rad(lat1)) * Math.cos(rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

exports.processLoanImage = onObjectFinalized({
    secrets: ["VERTEX_API_KEY"],
    timeoutSeconds: 300,
    memory: "512MiB"
}, async (event) => {
    const fileBucket = event.data.bucket;
    const filePath = event.data.name;
    const contentType = event.data.contentType;
    const systemMetadata = event.data.metadata || {};
    const customMetadata = systemMetadata.metadata || systemMetadata;

    const { lat, lng, time, userId, loanId, isBill } = customMetadata;

    if (!loanId || !userId) return null;

    const loanRef = db.collection("loans").doc(loanId);

    // 1. Setup/Fetch Document
    await loanRef.set({
        userId,
        status: "initialised",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    const loanDoc = await loanRef.get();
    const loanData = loanDoc.data();

    // Check if it's a bill (Using the flag from Flutter)
    const isBillFile = isBill === 'true' || filePath.toLowerCase().includes("bill");

    // 2. Precise Time Validation
    const uploadTime = new Date(time);
    const now = new Date();

    // Use Math.abs for the diff to handle slight server/phone clock drifts
    const diffMs = now.getTime() - uploadTime.getTime();
    const diffMinutes = diffMs / (1000 * 60);

    console.log(`File: ${filePath} | Diff: ${diffMinutes.toFixed(2)} mins | isBill: ${isBillFile}`);

    // LOGIC: Only reject assets if they are ancient (allowing a 2-min buffer for "future" drift)
    const isExpired = !isBillFile && (diffMinutes > 15 || diffMinutes < -2);

    if (!lat || !lng || isExpired) {
        const reason = isExpired ? `Photo is too old (${diffMinutes.toFixed(1)} mins)` : "GPS data missing";
        await loanRef.update({
            status: "rejected",
            rejectionReason: reason,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
        return null;
    }

    const incomingLat = parseFloat(lat);
    const incomingLng = parseFloat(lng);
    const geoPoint = new admin.firestore.GeoPoint(incomingLat, incomingLng);

    // 3. Proximity Check
    if (!isBillFile && loanData.assetData && loanData.assetData.length > 0) {
        for (const asset of loanData.assetData) {
            const distance = getDistance(incomingLat, incomingLng, asset.location.latitude, asset.location.longitude);
            if (distance > 200) {
                await loanRef.update({
                    status: "rejected",
                    rejectionReason: `Location mismatch: ${Math.round(distance)}m apart.`,
                    lastUpdated: admin.firestore.FieldValue.serverTimestamp()
                });
                return null;
            }
        }
    }

    // 4. Update File Info FIRST (Ensures assetData is not empty)
    const fileEntry = {
        path: filePath,
        location: geoPoint,
        timestamp: time
    };

    if (isBillFile) {
        await loanRef.update({
            billData: fileEntry,
            status: loanData.status === "rejected" ? "rejected" : "pending",
        });
    } else {
        await loanRef.update({
            assetData: admin.firestore.FieldValue.arrayUnion(fileEntry),
            status: loanData.status === "rejected" ? "rejected" : "pending",
        });

        // 5. Run AI only if status isn't already rejected
        try {
            const model = vertexAI.getGenerativeModel({ model: "gemini-2.0-flash-lite" });
            const [url] = await admin.storage().bucket(fileBucket).file(filePath).getSignedUrl({
                action: 'read', expires: Date.now() + 60 * 60 * 1000,
            });

            const prompt = `Return ONLY JSON: { "confidence_score": number, "summary": "string" }. Audit asset for loan collateral.`;
            const result = await model.generateContent({
                contents: [{ role: "user", parts: [{ text: prompt }, { fileData: { fileUri: url, mimeType: contentType } }] }]
            });

            let rawText = result.response.candidates[0].content.parts[0].text;
            rawText = rawText.replace(/```json/g, "").replace(/```/g, "").trim();
            const ai = JSON.parse(rawText);

            await loanRef.update({
                confidence_score: ai.confidence_score,
                summary: ai.summary,
                status: ai.confidence_score > 70 ? "AI_VERIFIED" : "AI_FLAGGED"
            });
        } catch (e) {
            console.error("AI Fail:", e);
        }
    }

    return null;
});