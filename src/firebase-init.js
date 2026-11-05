import { initializeApp } from "https://www.gstatic.com/firebasejs/13.0.0/firebase-app.js";
import { getAnalytics, isSupported as analyticsSupported } from "https://www.gstatic.com/firebasejs/13.0.0/firebase-analytics.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/13.0.0/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/13.0.0/firebase-firestore.js";
import { getStorage } from "https://www.gstatic.com/firebasejs/13.0.0/firebase-storage.js";
import { firebaseConfig } from "./firebase-config.js";

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const storage = getStorage(app);
window.ativoFrotaFirebase = { app, auth, db, storage, projectId: firebaseConfig.projectId, status: "connected" };

analyticsSupported().then((supported) => {
  if (supported) window.ativoFrotaFirebase.analytics = getAnalytics(app);
}).catch(() => {});

document.dispatchEvent(new CustomEvent("ativofrota:firebase-ready", { detail: window.ativoFrotaFirebase }));
