# CityShop — Apple App Store checklist

Publish **CityShop** on iPhone/iPad via App Store Connect and TestFlight.

You do **not** need an Android phone for Google Play either — both stores are set up on **Mac + web browser**. You only need an iPhone later to **test** via TestFlight.

---

## App details (already in repo)

| Item | Value |
|------|--------|
| Bundle ID | `com.cityshop.cityshopMobile` |
| Display name | CityShop |
| Version | See `pubspec.yaml` (e.g. 1.0.152+153) |
| Min iOS | 13.0 |
| Permissions | Camera, mic, photos (already in Info.plist) |

---

## Part A — Apple Developer account (do this now on Mac/web)

### Step 1: Enroll in Apple Developer Program

1. Go to **https://developer.apple.com/programs/enroll/**
2. Sign in with Apple ID (use a stable account — Robert or Hermes studio email linked to iCloud)
3. Choose **Individual** (same as Play Store — fastest) or **Organization** (needs D-U-N-S like Google)
4. Pay **$99 USD / year**
5. Wait for approval (usually **24–48 hours**, can be longer)

> Unlike Play Store ($25 once), Apple is **$99 every year**.

### Step 2: App Store Connect

1. Go to **https://appstoreconnect.apple.com**
2. Sign in with the same Apple ID
3. Accept agreements if prompted
4. **Users and Access** — add team members if needed

---

## Part B — Create the app in App Store Connect (no iPhone needed)

1. App Store Connect → **Apps** → **+** → **New App**
2. Fill in:

| Field | Value |
|-------|--------|
| Platforms | iOS |
| Name | CityShop |
| Primary language | English (U.S.) |
| Bundle ID | `com.cityshop.cityshopMobile` (register first if missing — see Step 3) |
| SKU | `cityshop-mobile` (any unique string) |
| User access | Full access |

### Step 3: Register Bundle ID (if not in dropdown)

1. **https://developer.apple.com/account/resources/identifiers/list**
2. **+** → **App IDs** → **App**
3. Description: **CityShop**
4. Bundle ID: **Explicit** → `com.cityshop.cityshopMobile`
5. Enable capabilities if needed:
   - **Push Notifications** (for order alerts)
   - **Associated Domains** (for `cityunlock.net` deep links — optional for v1)
6. Register

---

## Part C — Xcode signing (on your Mac)

### Step 1: Open project in Xcode

```bash
cd /Users/apple/Desktop/ACE/cityshop/mobile
open ios/Runner.xcworkspace
```

If `.xcworkspace` missing, run `flutter pub get` first.

### Step 2: Set signing

1. Select **Runner** project → **Runner** target
2. **Signing & Capabilities**
3. Check **Automatically manage signing**
4. **Team** → select your Apple Developer team
5. **Bundle Identifier** → `com.cityshop.cityshopMobile`

Repeat for **Release** configuration.

### Step 3: Optional — Push notifications (Firebase)

iOS push needs `GoogleService-Info.plist` in `ios/Runner/` from Firebase console (same project as Android). Without it, push may not work on iPhone until added.

---

## Part D — Build upload file (.ipa)

### Option 1: Xcode (easiest first time)

1. Xcode → product menu → **Archive**
2. Wait for archive → **Organizer** opens
3. **Distribute App** → **App Store Connect** → **Upload**
4. Follow prompts

### Option 2: Terminal script

After Xcode team is set:

```bash
cd /Users/apple/Desktop/ACE/cityshop/mobile
chmod +x scripts/build-appstore-ios.sh
bash scripts/build-appstore-ios.sh
```

Output: `build/appstore/CityShop-1.0.152-153.ipa`

### Option 3: Transporter app

1. Download **Transporter** from Mac App Store
2. Drag the `.ipa` file → **Deliver**

---

## Part E — TestFlight (internal testing — iPhone needed here)

1. App Store Connect → **CityShop** → **TestFlight**
2. Wait for build processing (**10–30 min** after upload)
3. **Internal Testing** → add testers by Apple ID email
4. Testers install **TestFlight** app on iPhone → accept invite → install CityShop

> This is when you need an iPhone — not for account setup, only for testing.

---

## Part F — App Store listing (before public release)

Complete in App Store Connect → **CityShop** → **App Store** tab:

| Item | Required |
|------|----------|
| Screenshots | 6.7" and 6.5" iPhone (min 3 each) — use Simulator or real device |
| Description | Shopping/marketplace copy (see below) |
| Keywords | shop, ghana, marketplace, cityshop |
| Support URL | https://cityunlock.net |
| Privacy Policy URL | https://cityunlock.net/privacy (**must publish on website**) |
| Category | Shopping |
| Age rating | Complete questionnaire (likely 4+ or 12+ due to payments) |
| App Privacy | Declare data collected (account, address, photos, payments) |

**Description (copy/paste):**

```
CityShop is Ghana's marketplace to discover local sellers, shop products, and pay securely.

• Browse stores and products
• Delivery addresses across all 16 Ghana regions
• Wallet and mobile money payments
• Order tracking
• Live shopping features

Create a buyer account to shop, or apply to sell on CityShop.
```

---

## Part G — Submit for review

1. App Store Connect → **CityShop** → **App Store** → **+ Version** (e.g. 1.0.152)
2. Select the uploaded build
3. Complete **Export Compliance** (usually "No" for encryption if using standard HTTPS only)
4. **App Review Information** — provide test login:

| Field | Example |
|-------|---------|
| Username | test buyer phone/email |
| Password | test password |
| Notes | "Marketplace app for Ghana. Sign in to browse and shop." |

5. **Submit for Review**
6. Review typically **1–3 days** (first submission can take longer)

---

## Play Store vs App Store — what you can do without phones

| Task | Android phone? | iPhone? | Where |
|------|----------------|---------|--------|
| Developer account signup | No | No | Web browser |
| Upload build | No | No | Mac (AAB or IPA) |
| Store listing / privacy | No | No | Web browser |
| Internal testing install | Yes (optional) | Yes (TestFlight) | Phone |

---

## Quick reference — parallel timeline

| Week | Google Play | Apple App Store |
|------|-------------|-----------------|
| Now | Finish Play Console signup on Mac | Enroll at developer.apple.com ($99) |
| Day 1–2 | Upload `CityShop-PlayStore.aab` | Create app in App Store Connect |
| Day 2–3 | Internal testing | Xcode Archive → Upload IPA |
| Day 3–5 | Production after testing | TestFlight → App Review |

---

## Files & commands

```bash
# Play Store (already done)
Desktop/CityShop-PlayStore.aab

# App Store (after Xcode signing)
cd cityshop/mobile
bash scripts/build-appstore-ios.sh
```

---

## Still required for BOTH stores

1. **Privacy policy** at https://cityunlock.net/privacy
2. **Screenshots** (Android + iPhone sizes differ)
3. **Test account** for reviewers
4. **Support email**

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No Team in Xcode | Apple Developer enrollment not approved yet |
| Bundle ID mismatch | Use exactly `com.cityshop.cityshopMobile` |
| Archive greyed out | Select "Any iOS Device" not Simulator |
| Missing compliance | Answer export encryption questions in App Store Connect |
| Push not working on iOS | Add `GoogleService-Info.plist` from Firebase |

---

## Links

- Apple Developer: https://developer.apple.com
- App Store Connect: https://appstoreconnect.apple.com
- Transporter: Mac App Store
- Flutter iOS deploy: https://docs.flutter.dev/deployment/ios
