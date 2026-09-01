# CityShop — Google Play Store checklist

Use this guide to publish **CityShop** (`com.cityshop.cityshop_mobile`) on Google Play.

---

## What is already done in the repo

| Item | Status |
|------|--------|
| App ID | `com.cityshop.cityshop_mobile` |
| App name | CityShop |
| Version | See `pubspec.yaml` (e.g. 1.0.152+153) |
| Release signing Gradle config | `android/app/build.gradle.kts` |
| Keystore generator script | `scripts/generate-release-keystore.sh` |
| AAB build script | `scripts/build-playstore-bundle.sh` |

---

## Part A — On your Mac (one-time setup)

### Step 1: Generate signing key

Open Terminal:

```bash
cd /Users/apple/Desktop/ACE/cityshop/mobile
chmod +x scripts/*.sh
bash scripts/generate-release-keystore.sh
```

This creates:

- `android/app/cityshop-release.keystore` — **back this up forever**
- `android/key.properties` — passwords (gitignored)
- `android/PLAYSTORE_SIGNING.local.txt` — copy passwords to 1Password / secure drive

> If you lose the keystore, you **cannot** update the app on Play Store.

### Step 2: Build the Play Store file (.aab)

```bash
bash scripts/build-playstore-bundle.sh
```

Output:

`build/playstore/CityShop-1.0.152-153.aab`

Upload **this .aab file** to Google Play (not the APK on Desktop).

---

## Part B — Google Play Console (Robert / business owner)

### Step 3: Create developer account

1. Go to **https://play.google.com/console**
2. Sign in with a Google account Robert controls
3. Pay **$25** one-time registration fee
4. Complete **identity verification** (can take 1–7 days)
5. Choose account type: **Organization** (if CityUnlock is a company) or **Individual**

### Step 4: Create the app

1. Play Console → **Create app**
2. **App name:** CityShop
3. **Default language:** English (United States) or English (Ghana)
4. **App or game:** App
5. **Free or paid:** Free
6. Accept policies → **Create app**

### Step 5: Set up the app (required before publishing)

Complete every item under **Policy and programs** and **Grow**:

#### 5a. App access

- If login is required: select **All functionality requires login**
- Provide test account for Google reviewers:

  | Field | Example |
  |-------|---------|
  | Email / phone | `reviewer@cityunlock.net` or a real test buyer account |
  | Password | (create a dedicated test account) |
  | Instructions | "Sign in → browse products → add to cart. Wallet optional." |

#### 5b. Ads

- Select **No, my app does not contain ads** (unless you added ads)

#### 5c. Content rating

1. **Start questionnaire** → category: likely **Shopping** or **Utilities**
2. Answer honestly (marketplace, user content, payments)
3. Submit → get IARC rating (usually Everyone or Teen)

#### 5d. Target audience

- Select age groups (likely **18+** if wallet/payments; or **13+** if general shopping)
- Not primarily for children

#### 5e. News app

- **No**

#### 5f. COVID-19 apps

- **No**

#### 5g. Data safety

Declare what CityShop collects (based on the app):

| Data type | Collected? | Purpose |
|-----------|------------|---------|
| Name, email, phone | Yes | Account, orders, KYC |
| Address | Yes | Delivery |
| Photos / videos | Yes | Product listings, KYC, livestream |
| Financial info | Yes | Wallet, MoMo, payments |
| Device ID | Yes | Push notifications (FCM) |
| Location | Optional | If you use GPS for delivery |

- Data is **encrypted in transit** (HTTPS)
- Users can **request account deletion** (provide support email)
- Link privacy policy URL (see Step 6)

#### 5h. Government apps

- **No**

#### 5i. Financial features

- If asked: app includes **digital wallet** and **mobile money** — describe as marketplace payments in Ghana

---

### Step 6: Privacy policy (REQUIRED)

Play Store requires a **public privacy policy URL**.

You need a page like:

**https://cityunlock.net/privacy**

(or `/privacy-policy`)

It must explain: account data, orders, wallet, KYC documents, camera/mic for livestream, push notifications, third parties (Firebase, payment providers).

> **Action needed:** Publish a privacy policy page on the website before submitting.

Support email for the listing: use your real support address (e.g. `support@cityunlock.net` or Robert's business email).

---

### Step 7: Store listing (Main store listing)

Go to **Grow → Store presence → Main store listing**

| Field | What to enter |
|-------|----------------|
| **App name** | CityShop |
| **Short description** (80 chars) | Shop local stores in Ghana. Pay with wallet, MoMo, and secure checkout. |
| **Full description** | See copy below |
| **App icon** | 512×512 PNG (use CityShop logo) |
| **Feature graphic** | 1024×500 PNG (banner image) |
| **Phone screenshots** | Min 2, recommended 4–8 (signup, home, product, cart/checkout) |
| **Category** | Shopping |
| **Email** | Support email |
| **Website** | https://cityunlock.net |

**Full description (copy/paste):**

```
CityShop is Ghana's marketplace to discover local sellers, shop products, and pay securely.

• Browse stores and products near you
• Add delivery addresses across all 16 regions
• Pay with wallet, mobile money, and more
• Track orders from checkout to delivery
• Live shopping and seller tools

Create a buyer account to shop, or apply to sell on CityShop.

Support: [your support email]
Website: https://cityunlock.net
```

---

### Step 8: Upload the app (Internal testing first)

1. Play Console → **Testing → Internal testing**
2. **Create new release**
3. **Upload** the `.aab` from `build/playstore/`
4. **Release name:** 1.0.152 (or current version)
5. **Release notes:** Full Ghana region/city lists, signup and address pickers, bug fixes.
6. **Save** → **Review release** → **Start rollout to Internal testing**

### Step 9: Add testers

1. **Testing → Internal testing → Testers**
2. Create email list → add Robert's Gmail + your team
3. Copy the **opt-in link** and open on Android phones
4. Install from Play Store (not APK)

### Step 10: Production (after testing)

1. Fix any issues from internal testing
2. **Promote release** to **Production** (or Closed → Open → Production)
3. **Submit for review** (first review often **3–7 days**, longer for finance/marketplace apps)
4. When approved, app is live on Play Store

---

## Part C — Enable Google Play App Signing (recommended)

On first upload, Play Console will ask:

**Let Google manage your app signing key** → choose **Yes** (recommended)

- Google holds the final signing key
- Your `cityshop-release.keystore` becomes the **upload key**
- Safer if upload key is ever lost (Google can reset it)

---

## Part D — Each new version (updates)

1. Bump version in `pubspec.yaml` (e.g. `1.0.153+154`)
2. Commit and push
3. Run:

```bash
cd cityshop/mobile
bash scripts/build-playstore-bundle.sh
```

4. Play Console → new release → upload new `.aab` → rollout

---

## Quick reference — who does what

| Task | Who | Where |
|------|-----|--------|
| Generate keystore + build .aab | You (Mac) | Terminal scripts above |
| Play Developer $25 account | Robert | play.google.com/console |
| Privacy policy page | You / Robert | cityunlock.net website |
| Store screenshots & graphics | Robert / designer | Play Console listing |
| Test account for Google | You | Play Console → App access |
| Upload .aab & submit | Robert | Play Console → Internal testing |
| Tester install link | Robert | Share opt-in URL with team |

---

## Files you must never lose

1. `android/app/cityshop-release.keystore`
2. `android/PLAYSTORE_SIGNING.local.txt` (passwords)
3. Google Play Console login

Back up all three in secure storage.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Upload key not valid" | Rebuild with `build-playstore-bundle.sh` after keystore is set up |
| "Privacy policy required" | Publish `/privacy` on website first |
| "App not compatible" | Check `minSdk` in Flutter — most phones are fine |
| Review rejected for payments | Provide test account + explain wallet is for marketplace only |
| AAB build fails | Set `JAVA_HOME` to Android Studio JBR (script does this on Mac) |

---

## Support links

- Play Console: https://play.google.com/console
- Flutter Android deployment: https://docs.flutter.dev/deployment/android
- App signing help: https://support.google.com/googleplay/android-developer/answer/9842756
