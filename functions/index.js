const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { VertexAI } = require("@google-cloud/vertexai");
const admin = require("firebase-admin");

admin.initializeApp();

// 1. Configure Vertex AI
const project = process.env.GCLOUD_PROJECT;
const location = "us-central1";
const vertexAI = new VertexAI({ project: project, location: location });

// 2. Define the Structured Response Schema for Gemini
const verificationSchema = {
    type: "object",
    properties: {
        is_asset_match: { type: "boolean", description: "Does the photo match the item on the bill?" },
        confidence_score: { type: "integer", description: "Confidence 0-100" },
        detected_asset: { type: "string" },
        fraud_alerts: { type: "array", items: { type: "string" } },
        summary: { type: "string" }
    },
    required: ["is_asset_match", "confidence_score", "summary"]
};

exports.processLoanImage = onObjectFinalized({
    secrets: ["VERTEX_API_KEY"]
}, async (event) => {
    const fileBucket = event.data.bucket;
    const filePath = event.data.name;
    const contentType = event.data.contentType;
    const metadata = event.data.metadata || {};

    // Ignore non-image files
    if (!contentType.startsWith("image/")) return null;

    // --- STAGE 1: METADATA GATEKEEPER ---
    const { latitude, longitude, timestamp, userId } = metadata;
    const uploadTime = new Date(timestamp);
    const now = new Date();

    // Basic validation: Check if metadata exists and is recent (within 15 mins)
    const isExpired = (now - uploadTime) / 1000 / 60 > 15;
    if (!latitude || !longitude || isExpired) {
        console.warn(`Validation failed for ${filePath}. Deleting...`);
        const bucket = admin.storage().bucket(fileBucket);
        await bucket.file(filePath).delete();

        // Log the rejection to Firestore for the user/officer to see
        if (userId) {
            await admin.firestore().collection("rejections").add({
                userId, filePath, reason: "Invalid or expired metadata", createdAt: admin.firestore.FieldValue.serverTimestamp()
            });
        }
        return null;
    }

    // --- STAGE 2: MULTIMODAL AI ANALYSIS ---
    try {
        const model = vertexAI.getGenerativeModel({
            model: "gemini-2.0-flash-lite",
            generationConfig: {
                responseMimeType: "application/json",
                responseSchema: verificationSchema
            },
        });

        // Get a signed URL for Gemini to access the private file
        const [url] = await admin.storage().bucket(fileBucket).file(filePath).getSignedUrl({
            action: 'read',
            expires: Date.now() + 60 * 60 * 1000, // Current time + 1 hour in milliseconds
        });

        const prompt = `Analyze this image for loan verification. Verify if the asset matches the expected loan category. Check for signs of re-photography or digital tampering.`;

        const result = await model.generateContent({
            contents: [{
                role: "user",
                parts: [
                    { text: prompt },
                    { fileData: { fileUri: url, mimeType: contentType } }
                ]
            }]
        });

        const aiResponse = JSON.parse(result.response.candidates[0].content.parts[0].text);

        // --- STAGE 3: SAVE TO FIRESTORE ---
        await admin.firestore().collection("loan_verifications").add({
            userId,
            filePath,
            location: { lat: parseFloat(latitude), lng: parseFloat(longitude) },
            aiResult: aiResponse,
            status: aiResponse.is_asset_match ? "AI_VERIFIED" : "AI_REJECTED",
            verifiedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        console.log(`Successfully processed ${filePath}`);
    } catch (error) {
        console.error("AI Analysis Error:", error);
    }
});