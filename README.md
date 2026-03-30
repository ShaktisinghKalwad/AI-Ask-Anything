# AI-Ask-Anything
A simple ChatGPT-style AI chat interface powered by the OpenAI Chat Completions API.
A built-in Math Puzzles mini-game with timed/practice modes, scoring, streak tracking, adaptive difficulty, and shareable results.

# Key Features
## 1) AI Chat (OpenAI)
- Endpoint used: https://api.openai.com/v1/chat/completions
- Model configured: gpt-3.5-turbo
- Behavior: User sends a message.
- App attempts to fetch a response from OpenAI (15s timeout).
- If the API fails, the app falls back to an offline response generator based on keywords (Flutter, AI, Python, JavaScript, etc.).

## 2) Chat UX & Utilities
- Message bubbles for user and AI with optional timestamps.
- Long-press actions on messages: Copy, Favorite / Unfavorite, Edit & resend (user messages only), Delete
- Favorites view: toggle to show only starred messages.
- Conversation controls: Start new conversation, Clear chats (with confirmation)
- Settings screen: Theme selection, Chat font size slider (scale)
Export conversation as plain text: Copy to clipboard, Share via system share sheet

## 3) Math Puzzles Mini‑Game
- A dedicated screen called Math Puzzles that includes:
- Modes: Timed (60 seconds), Practice (no timer)
- Difficulty: Easy / Medium / Hard, Includes an adaptive adjustment mechanism in timed mode based on recent accuracy.
- Gameplay: Multiple-choice answers (4 options), Tracks score, streak, accuracy, fastest answer time, End-of-round summary dialog with “Share” option
- Online dependency:Fetches random numbers from: https://www.randomnumberapi.com/api/v1.0/random?...
- Uses connectivity_plus to detect connectivity and blocks gameplay when offline.

## 4) Ads (Google Mobile Ads / AdMob)
- Uses interstitial ads via google_mobile_ads.
- Triggering behavior: Chat: attempts to show interstitial after AI responses (based on message count threshold).
- Math puzzles: shows interstitial at key moments (round end / restart flow).
- Android setup includes: INTERNET + ACCESS_NETWORK_STATE permissions, AdMob App ID in AndroidManifest.xml

# Tech Stack
- Framework: Flutter (Dart)
- State management: StatefulWidgets (simple local state)
- Networking: http
- Local persistence: shared_preferences
- Environment config: flutter_dotenv (loads .env as an asset)
- Sharing: share_plus
- Connectivity: connectivity_plus
- External links: url_launcher
- Ads: google_mobile_ads (AdMob interstitial)
