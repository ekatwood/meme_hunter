#!/bin/bash

# Load environment variables from .env file
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Check if the FIREBASE_API_KEY is set
if [ -z "$FIREBASE_API_KEY" ]; then
    echo "Error: FIREBASE_API_KEY not found in .env file."
    exit 1
fi

# Function to run the app in debug mode
run_app() {
    echo "Running app with --dart-define"
    flutter run -d chrome --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY"
}

# Function to build the app for web
build_web() {
    echo "Building web with --dart-define"
    flutter build web --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY"
}

# Main script logic
if [ "$1" == "build" ]; then
    build_web
elif [ "$1" == "run" ]; then
    run_app
else
    echo "Usage: ./run.sh [run|build]"
    echo "  run: Runs the app in debug mode."
    echo "  build: Builds the app for web."
fi