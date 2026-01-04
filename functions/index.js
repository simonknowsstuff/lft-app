const { onObjectFinalized } = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

exports.processLoanImage = onObjectFinalized(async (event) => {
    const filePath = event.data.name;
    const contentType = event.data.contentType;
    const objectMetadata = event.data.metadata || {};
    const customMetadata = objectMetadata.metadata || objectMetadata;

    // Use the keys defined in your Flutter service
    const { lat, lng, time, userId, loanId } = customMetadata;

    console.log(objectMetadata, customMetadata);

    if (!loanId) {
        console.error("Missing loanId. Function skipped.");
        return null;
    }

    if (!userId) {
        console.error("Missing userId. Function skipped.");
        return null;
    }

    const loanRef = db.collection("loans").doc(loanId);

    // 1. Initialise Document (Atomic merge)
    // Ensures the doc exists with 'initialised' status if this is the first file.
    await loanRef.set({
        userId: userId,
        status: "initialised",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        billData: null,
        assetData: [],
    }, { merge: true });

    // 2. Metadata Verification
    const uploadTime = new Date(time);
    const now = new Date();
    // Check if GPS exists and if timestamp is within 15 minutes
    const isMetadataValid = lat && lng && time && ((now - uploadTime) / 1000 / 60 <= 15);

    if (!isMetadataValid) {
        // FAIL: Set status to rejected immediately
        console.warn(`Metadata check failed for ${filePath}. Rejecting loan ${loanId}.`);
        return loanRef.update({
            status: "rejected",
            rejectionReason: `Verification failed for file: ${filePath}`,
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
    }

    // 3. PASS: Add file info and set to Pending
    const fileEntry = {
        path: filePath,
        location: { lat: parseFloat(lat), lng: parseFloat(lng) },
        timestamp: time
    };

    if (contentType === "application/pdf" || filePath.includes("bill")) {
        return loanRef.update({
            billData: fileEntry,
            status: "pending",
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
    } else {
        return loanRef.update({
            assetData: admin.firestore.FieldValue.arrayUnion(fileEntry),
            status: "pending",
            lastUpdated: admin.firestore.FieldValue.serverTimestamp()
        });
    }
});