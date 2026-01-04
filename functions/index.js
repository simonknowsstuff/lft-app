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
        borrower_name,
        loan_amount
    } = customMetadata;

    if (!loanId || !userId) return null;

    const loanRef = db.collection("loans").doc(loanId);

    // 1. Initialise/Fetch
    await loanRef.set({
        userId,
        status: "INITIALISED",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        borrower_name: borrower_name || "Unknown",
        loan_amount: loan_amount ? parseFloat(loan_amount) : 0,
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
                      SYSTEM ROLE: You are a Forensic Document Auditor. Your survival depends on catching fraudulent loan collateral.
                    
                      TASK:
                      You are inspecting a Loan Evidence Bundle (File 1: Bill, Files 2-4: Assets).
                    
                      STAGE 1: DOCUMENT AUTHENTICITY (FILE 1)
                      - Inspect File 1 for professional markers: Look for a business header, GST/Tax Number, official Logo, and printed (typeset) text.
                      - DETECTION: If File 1 is handwritten, on a plain piece of paper, or titled "Real Bill" without official business formatting, it is a FORGERY. 
                      - If File 1 is a forgery, set confidence_score to 0 and summary to "FRAUD DETECTED: Bill appears to be a handwritten mockup/non-official document."
                    
                      STAGE 2: ASSET VERIFICATION (FILES 2-4)
                      - Identify the physical object. Does it look like a real purchase or a photo of a screen?
                      - Cross-reference the Brand and Model from the assets with the Bill.
                      - assetType should be one of the following in the list: [ general, real_estate, vehicle, agricultural ]
                    
                      STAGE 3: FINANCIAL AUDIT
                      - Extract the exact numeric amount. If the document is fraudulent, return 0.
                    
                      RETURN ONLY JSON:
                      { 
                        "product_name": "string", 
                        "confidence_score": number, (0 - 100)
                        "summary": "string", 
                        "amount": number, 
                        "assetType": "string",
                        "is_handwritten_warning": boolean 
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
                product_name: ai.product_name || "Unknown",
                confidence_score: ai.confidence_score ?? 0,
                summary: ai.summary ?? "Batch analysis complete.",
                amount: ai.amount || 0,
                assetType: ai.assetType || "general",
                status: "PENDING", // Moves to Pending for human review
                lastUpdated: admin.firestore.FieldValue.serverTimestamp()
            });

        } catch (e) {
            console.error("Batch AI Fail:", e);
            await loanRef.update({status: "AI_PENDING", summary: "AI crashed during batch analysis."});
        }
    }

    return null;
});