// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyALnkP4pw4ufkZ09EUSj9Rhc4TnwWPxy4o",
  authDomain: "meme-hunter-4f1c1.firebaseapp.com",
  projectId: "meme-hunter-4f1c1",
  storageBucket: "meme-hunter-4f1c1.firebasestorage.app",
  messagingSenderId: "194957573763",
  appId: "1:194957573763:web:e37d34fc282d546a6c25b6",
  measurementId: "G-P5JJPQXTGK"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);