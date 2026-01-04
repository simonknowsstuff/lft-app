const { onObjectFinalized } = require("firebase-functions/v2/storage");
const { VertexAI } = require("@google-cloud/vertexai");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();
db.settings({ignoreUndefinedProperties: true});

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

    console.log("Full Metadata Received:", JSON.stringify(customMetadata));

    const {
        lat,
        lng,
        time,
        userId,
        loanId,
        isBill,
        borrowerName,
        loanAmount,
        selectedAssetType
    } = customMetadata;

    if (!loanId || !userId) return null;

    const loanRef = db.collection("loans").doc(loanId);

    // 1. Initialise/Fetch
    await loanRef.set({
        userId,
        status: "INITIALISED",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        borrowerName: borrowerName || "Unknown",
        loanAmount: loanAmount ? parseFloat(loanAmount) : 0,
        selectedAssetType: selectedAssetType || "general"
    }, { merge: true });

    let loanDoc = await loanRef.get();
    let loanData = loanDoc.data();

    // Rejection guard: If already rejected by a previous file, stop.
    if (loanData.status === "REJECTED") return null;

    const isBillFile = isBill === 'true' || filePath.toLowerCase().includes("bill");

    // 2. Metadata Gatekeeper
    const uploadTime = new Date(time);
    const now = new Date();

    if (isNaN(uploadTime.getTime())) {
        return loanRef.update({
            status: 'REJECTED',
            rejectionReason: "Invalid timestamp format"
        });
    }

    const diffMs = now.getTime() - uploadTime.getTime();
    const diffMinutes = Math.abs(diffMs / (1000 * 60));

    console.log(`Current Server Time (UTC): ${now.toISOString()}`);
    console.log(`Device Upload Time: ${uploadTime.toISOString()}`);
    console.log(`Calculated Difference: ${diffMinutes.toFixed(2)} minutes`);

    const isExpired = !isBillFile && diffMinutes > 15;

    if (!lat || !lng || isExpired) {
        return loanRef.update({
            status: "REJECTED",
            rejectionReason: isExpired ? `Photo expired (${diffMinutes.toFixed(0)}m ago)` : "GPS missing",
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
    }

    const incomingLat = parseFloat(lat);
    const incomingLng = parseFloat(lng);
    const geoPoint = new admin.firestore.GeoPoint(incomingLat, incomingLng);

    // 3. Proximity Check
    if (!isBillFile && loanData.assetData && loanData.assetData.length > 0) {
        for (const asset of loanData.assetData) {
            const dist = getDistance(incomingLat, incomingLng, asset.location.latitude, asset.location.longitude);
            if (dist > 200) {
                return loanRef.update({status: "REJECTED", rejectionReason: "Location mismatch"});
            }
        }
    }

    // 4. Update File Arrays
    const fileEntry = {path: filePath, location: geoPoint, timestamp: time, contentType: contentType};

    if (isBillFile) {
        await loanRef.update({billData: fileEntry, status: "AI_PENDING"});
    } else {
        await loanRef.update({
            assetData: admin.firestore.FieldValue.arrayUnion(fileEntry),
            status: "AI_PENDING"
        });
    }

    // REFRESH data to check if we are ready for AI
    loanDoc = await loanRef.get();
    loanData = loanDoc.data();

    // 5. THE BATCH AI TRIGGER
    // Only run if we have a bill AND exactly 3 assets
    const readyForAI = loanData.billData && loanData.assetData && loanData.assetData.length === 3;

    if (readyForAI) {
        try {
            const model = vertexAI.getGenerativeModel({
                model: "gemini-2.5-flash-lite",
                generationConfig: {responseMimeType: "application/json", temperature: 0.1}
            });

            // Construct parts: [Prompt, Bill, Asset1, Asset2, Asset3]
            const parts = [
                {
                    text: `
                      SYSTEM ROLE: You are a Lead Forensic Auditor for a Digital Bank. 
                      Your task is to approve or reject a loan collateral bundle based on File 1 (Bill) and Files 2-4 (Assets).
                    
                      TASK 1: DOCUMENT AUTHENTICITY (FILE 1)
                      - Verify if File 1 is an official printed invoice with business headers, Tax IDs, and professional formatting.
                      - If File 1 is handwritten, on a plain piece of paper, or lacks official markers, set confidence_score to 0 and summary to "FRAUD: Handwritten or non-official bill document."
                    
                      TASK 2: ASSET SIMILARITY & DUPLICATION (FILES 2-4)
                      - EXACT DUPLICATES: Are any of the 3 asset photos identical? If yes, set confidence_score to 0.
                      - NEAR-DUPLICATES: Did the user take "burst" photos from the same angle without moving? (Look at background and perspective). If photos are too similar, flag this.
                      - OBJECT CONSISTENCY: Do all 3 photos show the EXACT same physical item (check scratches, serials, color)?
                      - RANDOMNESS: Is one of the images completely unrelated (e.g., a photo of a cat or a different room)? If yes, set confidence_score to 0.
                    
                      TASK 3: EXTRACTION
                      - If there is a mismatch between the selected asset type of the user from the images from the actual images, lower the confidence score significantly.
                      - Extract the exact Amount from the Bill.
                      - Make the summary as descriptive as possible.
                    
                      RETURN ONLY JSON:
                      {
                        "productName": "string",
                        "confidenceScore": number, (0-100)
                        "summary": "string",
                        "amount": number,
                        "assetType": "string",
                        "isHandwritten": boolean,
                        "isDuplicate": boolean
                      }
                    `
                }
            ];

            // Add Bill
            parts.push({
                fileData: {
                    fileUri: `gs://${fileBucket}/${loanData.billData.path}`,
                    mimeType: loanData.billData.contentType
                }
            });

            // Add all 3 Assets
            loanData.assetData.forEach(asset => {
                parts.push({fileData: {fileUri: `gs://${fileBucket}/${asset.path}`, mimeType: "image/jpeg"}});
            });

            const result = await model.generateContent({contents: [{role: "user", parts}]});
            let rawText = result.response.candidates[0].content.parts[0].text;
            rawText = rawText.replace(/```json/g, "").replace(/```/g, "").trim();
            const ai = JSON.parse(rawText);

            await loanRef.update({
                productName: ai.productName || "Unknown",
                confidenceScore: ai.confidenceScore ?? 0,
                summary: ai.summary ?? "Batch analysis complete.",
                amount: ai.amount || 0,
                assetType: ai.assetType || "general",
                status: "PENDING", // Moves to Pending for human review
                isHandwritten: ai.isHandwritten || false,
                isDuplicate: ai.isDuplicate || false,
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

        } catch (e) {
            console.error("Batch AI Fail:", e);
            await loanRef.update({status: "AI_PENDING", summary: "AI crashed during batch analysis."});
        }
    }

    return null;
});