# TestFlight: every app change on main, on the phone (2026-09-23)

The owner approved it today: every build that passes should reach his iPhone
through TestFlight, and he makes one App Store Connect API key and pastes it
into GitHub once. `.github/workflows/testflight.yml` does the rest. Each push
to `main` that changes the app is archived for a device, signed through
Apple's cloud, uploaded, and followed until App Store Connect has processed it.
The TestFlight app then shows it with the commits it brought under
**What to Test**. `main` only ever receives a commit the branch has already
built, tested and photographed (`build.yml`, CLAUDE.md), so everything that
reaches TestFlight has passed.

This file is the owner's one-time setup (§1), what a run does (§2), the
options weighed and why this one (§3), the build numbers (§4), Xcode and the
runner (§5), what the phone gets (§6), what a red run means (§7), the app's
size (§8), the key's safety (§9) and what was checked here (§10).

Tags, as in `Docs/STORE.md`: **[live]** was read today from Apple's or
GitHub's own pages or from working pipelines; **[recall]** is from memory.

---

## 1. The owner's setup (once, about twenty minutes)

You need the paid Apple Developer Program. TestFlight, Sign in with Apple and
iCloud all require it, and the game already uses the last two.

### A. developer.apple.com

1. Open https://developer.apple.com/account → **Membership details**. Copy
   the **Team ID** (ten letters and digits, like `A1B2C3D4E5`). It is the
   value of the `APPLE_TEAM_ID` secret in step 12.
2. **Certificates, Identifiers & Profiles** → **Identifiers**. Look for
   **com.pantheon.game** in the list.
   - **If it is there** (Xcode registered it the first time you ran the game
     on your phone): click it and go to step 3.
   - **If it is not:** press **+** → **App IDs** → **Continue** → **App** →
     **Continue** → Description `Pantheon`, **Explicit** Bundle ID
     `com.pantheon.game` → tick **iCloud** and **Sign In with Apple** →
     **Continue** → **Register**. Then click it in the list. [live]
   - **If the portal says the identifier is not available**, another team
     owns it. Stop and tell Claude: the bundle id must change in the
     project, and that is a code change.
3. On the App ID's page, **Sign In with Apple** must be ticked. If it is not:
   **Edit** → tick it → **Configure** → leave **Enable as a primary App ID**
   → **Save** → **Save** (top right) → **Confirm**. [live]
4. Same page, **iCloud** must be ticked with CloudKit support, and the
   container **iCloud.com.pantheon.game** assigned to it. Check with
   **Edit** next to iCloud: `iCloud.com.pantheon.game` should be ticked in
   the table. If it is not, tick it → **Continue** → **Save** → **Confirm**.
   [live]
   - **If `iCloud.com.pantheon.game` is not in that table at all:** in
     **Identifiers**, switch the menu at the top right from App IDs to
     **iCloud Containers** → **+** → **iCloud Containers** → **Continue** →
     Description `Pantheon`, Identifier `iCloud.com.pantheon.game` →
     **Continue** → **Register**. Then repeat step 4. [recall]

   Why steps 3 and 4: the export builds the App Store profile from the App
   ID's capabilities. A capability missing here stops the run with
   "Provisioning profile … doesn't include …" rather than shipping a build
   whose sign-in or cloud save is dead.
5. Open the CloudKit Console (https://icloud.developer.apple.com) →
   **iCloud.com.pantheon.game** → **Deploy Schema Changes…** → deploy to
   **Production** (`Docs/SOCIAL.md`, *The owner's Xcode steps* 9 and
   *Sign in with Apple* 7). A TestFlight build reads iCloud's **Production**
   database, while every build from Xcode wrote to Development. Without this
   step the cloud save and the Allies screen fail in the TestFlight build.
   The save on the phone itself is unaffected. Deploy again whenever a new
   record type or field appears in Development.

### B. appstoreconnect.apple.com

6. **Apps** → **+** (top left) → **New App**, then fill the dialog [live]:
   - **Platforms:** iOS
   - **Name:** `Pantheon`. If App Store Connect answers that the name is
     taken, make it unique, for example `Pantheon: Gods of the Isle`. This
     is only the App Store name. The name under the icon stays "Pantheon",
     which comes from the build.
   - **Primary Language:** English (U.S.)
   - **Bundle ID:** `com.pantheon.game`, picked from the menu. If it is
     missing, step 2 was not saved.
   - **SKU:** `pantheon-game`
   - **User Access:** Full Access

   Press **Create**. The same record carries the in-app purchases of
   `Docs/STORE.md` §8.
7. **Users and Access** → **Integrations** tab → **App Store Connect API**
   (left column). [live]
   - **If a Request Access button shows** (the first time on an account):
     press it, tick the terms, press **Submit**. Apple reviews the request
     ("case by case"); continue once the **Team Keys** tab appears. [live]
8. **Team Keys** tab → **Generate API Key** (or **+**) → Name
   `GitHub TestFlight` → Access **Admin** → **Generate**. [live]
   It must be a **Team** key with the **Admin** role:
   - The export signs with Apple's *cloud-managed* distribution
     certificate, and Apple refuses those to every other role ("You haven't
     been given access to cloud-managed distribution certificates"; an App
     Manager key can upload but cannot sign). [live]
   - An *Individual* key cannot reach the provisioning endpoints at all.
     [live]
9. On the new key's row press **Download API Key** → **Download**. The file
   `AuthKey_<Key ID>.p8` lands in Downloads. It can be downloaded ONCE, so
   keep a copy in your password manager. [live]
10. Copy two values from the same page [live]:
    - **Key ID:** hover the key's row → **Copy Key ID** (ten characters).
    - **Issuer ID:** near the top of the page → **Copy** (a long id with
      dashes).
11. There is no agreement to sign for TestFlight itself. The **Paid Apps**
    agreement is only for the in-app purchases (`Docs/STORE.md` §8). If a
    banner asks you to accept an updated **Program License Agreement**,
    accept it at developer.apple.com/account; uploads stop until you do.

### C. github.com/tjp040318/Budget-and-advice

12. **Settings** → **Secrets and variables** → **Actions** → **Secrets** tab →
    **New repository secret**. Add these four, each name exactly as written,
    pressing **Add secret** after each [recall]:

    | Name | Value |
    |---|---|
    | `ASC_KEY_ID` | the Key ID (step 10) |
    | `ASC_ISSUER_ID` | the Issuer ID (step 10) |
    | `ASC_KEY_P8` | the whole `.p8` file. Right-click it → **Open With** → **TextEdit**, then ⌘A, ⌘C and paste, the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines included |
    | `APPLE_TEAM_ID` | the Team ID (step 1) |

    A typo does no harm: the run's first job checks the shape of all four and
    says which one is wrong.
13. *Optional:* **Settings** → **General** → **Default branch** → switch it
    to `main`. GitHub shows the **Run workflow** button only for workflows on
    the default branch, which is still `claude/debt-payoff-scheduler-u46mj9`
    from the repository's first life. [live]
    - **With the switch:** Actions → **testflight** → **Run workflow** →
      branch `main` starts an upload by hand.
    - **Without it:** nothing is lost. Every push to `main` that changes the
      app still uploads, and Claude can start a run through GitHub's API.

### D. TestFlight

14. App Store Connect → **Apps** → **Pantheon** → **TestFlight** tab →
    **+** next to **Internal Testing** in the sidebar → name `Owner` → tick
    **Enable automatic distribution** → **Create**. [live]
15. Open the group → **Invite Testers** → tick yourself → **Add**. [live]
    Only App Store Connect users can be internal testers: the Account Holder,
    Admin, App Manager, Developer and Marketing roles. You are the Account
    Holder.
16. On the iPhone, install **TestFlight** from the App Store. When the first
    build has been processed (§2), an email invites you to test Pantheon.
    Open it on the iPhone → **View in TestFlight** → **Accept** →
    **Install**. [live] In TestFlight, open Pantheon and turn on
    **Automatic Updates**, so each new build installs itself. [recall]
    The TestFlight build replaces the one Xcode installed (same bundle id),
    and the save on the phone stays.

### E. The first run

17. Nothing more to do. The next push to `main` that changes the app starts
    the workflow; the push that brings this workflow to `main` is one. To
    watch it: **Actions** → **testflight** → the newest run. Its three jobs
    run in order:
    - **Check the setup:** under a minute.
    - **Archive and upload:** about 30 minutes.
    - **Wait for TestFlight:** 5 to 30 minutes, while Apple processes the
      build.

    When the third is green, the build is on TestFlight and the phone
    shows it within minutes. The run's **Summary** names the build number,
    the commit, the Xcode and the app's size.
18. If a job is red, §7 has the fix. The reason is printed at the end of
    the job's log and in the run's Summary.

---

## 2. What a run does

1. **Check the setup** (Linux, under a minute). The run leaves at once, grey
   with a notice, if it is not on `main` or any of the four secrets is
   missing. It is never red before the setup is done. A secret that is
   present but has the wrong shape (a Key ID that is not ten characters, a
   `.p8` that is not a private key) turns it red, naming that secret.
2. **Archive and upload** (macOS 15):
   1. Checks out the commit, without `Art/` and with all of main's history
      (for the build number).
   2. Picks the newest release Xcode, 26 or later (§5).
   3. Numbers the build (§4) and writes What to Test from the commits this
      push brought to main.
   4. Makes room on the disk if less than 12 GB is free (§8).
   5. **Archives** Release for `generic/platform=iOS`, *ad-hoc* signed (§3).
      The team and the build number are passed on the command line. The
      project's signing settings are untouched, so `build.yml`'s simulator
      job, which signs nothing, is too. If Xcode refuses the automatic ad-hoc
      archive over *signing* (never over code), it archives again in manual
      style.
   6. **Checks the archive** before anything leaves the runner:
      - Every entitlement of `Pantheon/Pantheon.entitlements` (Sign in with
        Apple, the iCloud container, CloudKit) is in the archive's
        signature, or the run stops.
      - The archive names its team.
      - `CFBundleVersion` is the build number.
      - `ITSAppUsesNonExemptEncryption` is NO (a warning if not).
      - The app is under App Store Connect's 4 GB: a warning at 90%, a stop
        at 100%.
   7. Deletes the compile products and the checkout's resources. The archive
      has its own copy.
   8. Writes the `.p8` into the runner's temp folder, readable by the job's
      user alone.
   9. **Signs and uploads** in one `xcodebuild -exportArchive` with
      `.github/ExportOptions.plist`, the team added at run time:
      - `method` app-store-connect, `destination` upload, `signingStyle`
        automatic.
      - `uploadSymbols` on, so TestFlight crash reports are symbolicated.
      - `manageAppVersionAndBuildNumber` off (§4).

      With the key and `-allowProvisioningUpdates`, Xcode makes or refreshes
      the App Store profile from the App ID and signs with the team's
      cloud-managed Apple Distribution certificate. The first run creates
      that certificate.
   10. Keeps the dSYMs as a 30-day artifact when under 250 MB, then deletes
       the key whatever happened.
3. **Wait for TestFlight** (Linux, up to an hour). It polls App Store
   Connect once a minute through its API. Each call mints its own
   20-minute token from the `.p8`, using Python's standard library and
   `openssl`, with nothing to install. The build ends in one of three ways:
   - **VALID:** the job writes **What to Test** (the build, its commit and
     the commits it brought to main). It adds the build to any internal
     group that is not distributing automatically, and reports the state
     TestFlight shows (`IN_BETA_TESTING`, `READY_FOR_BETA_TESTING`, or
     `MISSING_EXPORT_COMPLIANCE` with a warning).
   - **INVALID or FAILED:** the run turns red. Apple has emailed the
     Account Holder the ITMS code.
   - **Still processing after an hour:** a warning, not red. The build
     arrives when Apple finishes.

   A green upload alone is not a build on the phone. App Store Connect
   refuses a processed build only by email, so without this job a refused
   build would look green.

One upload runs at a time. A newer push waits instead of cancelling one that
is halfway to Apple, and of several waiting pushes GitHub keeps only the
newest; the ones it drops show as *cancelled*. A push that touches only
docs, tools or tests does not run at all: it would upload the same app
again under a new number. Any change under `Pantheon/`,
`Pantheon.xcodeproj/`, or to the workflow or its plist does run.

---

## 3. The options, and why this one

Researched 2026-09-23. Apple's documentation and forums, the GitHub runner
images and six public pipelines that upload to TestFlight were read
directly [live]. Four blogs on the subject (Codemagic's, Thuyen's, Teabyte's,
Thomas Levesque's) are refused by the network policy.

| | What it is | What the owner does | What breaks | Verdict |
|---|---|---|---|---|
| **A** | `xcodebuild` with an App Store Connect API key; an **ad-hoc** archive; cloud signing at the export | One Admin key and four secrets, once | Nothing expires. The one untested link (Apple accepting the ad-hoc archive) is Xcode Cloud's own recipe, and public pipelines upload to TestFlight with it | **Chosen** |
| B | A, but the archive signed for development (`-allowProvisioningUpdates` on the archive too) | Same | Each fresh runner mints an "Apple Development: Created via API" certificate whose private key dies with the machine. The next run fails with "private key is not installed in your keychain" (Bitrise #278, Apple forum 760819), or the team hits the certificate cap (hideoutgames/zremote #64). A development profile also needs a registered device | Rejected |
| C | A, but the archive unsigned (`CODE_SIGNING_ALLOWED=NO`) | Same | The export keeps only the entitlements carried by the archive's signature (Apple DTS, forum 720887). Sign in with Apple and iCloud would vanish from a green, uploaded, installable build. One public pipeline shipped two builds without push this way before moving to ad-hoc | Rejected |
| D | Manual signing: a distribution `.p12` and an App Store profile stored as secrets (GitHub's documented recipe) | Export a `.p12` from Keychain Access, make a profile, base64 both into three more secrets | Both expire every year; the profile must be remade whenever a capability changes | Sound, but more to do and to redo, for nothing A lacks |
| E | fastlane match | A second private repository for encrypted certificates, a passphrase, Ruby on the runner | More moving parts | Made for teams that share certificates; nothing here needs it |
| F | Xcode Cloud | Set up in Xcode (**Product → Xcode Cloud**), with GitHub access granted to Apple | Its logs live in App Store Connect, which this environment cannot reach, so a red build could only be read by the owner. It is a second CI outside the repository's review. 25 compute hours a month are included [recall], about 35–50 builds of a 3 GB app | The best signing of all, but it breaks the loop in which Claude reads every red run and fixes it |

**Why the ad-hoc archive is right** [live]:

- **How Xcode Cloud archives.** Its archive command passes
  `CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<team>` (Apple forum 756119,
  where copying it fixed a GitHub Actions pipeline).
- **It keeps the entitlements.** An ad-hoc signature carries them without a
  certificate, a profile or a device, and the export re-signs for the App
  Store with them intact.
- **It is proven in production.** Public workflows upload to TestFlight this
  way: iragm/fishauctions-app, lockdown-systems/cyd-mobile, yasyf/cc-present,
  and bounce12340/work-schedule (manual style). The last one asserts
  its entitlements in the archive after losing push to an unsigned one.
  This workflow does the same for every entitlement the project declares.

**Why an Admin key:** see step 8. App Store Connect refuses cloud-managed
certificates to an App Manager key [live: Apple forum 776036 and two
pipelines' own notes].

**The upload tool:** `xcodebuild -exportArchive` with `destination` upload
(Apple's own path, the Organizer's) rather than `altool`, Transporter or a
third-party action. It is one step and one tool. The processing wait is ours:
`apple-actions/upload-testflight-build` mints one token and never renews it,
so its wait dies at Apple's 20-minute limit (a pipeline's own note [live]).

---

## 4. Build numbers

**Build N is commit N on main** (`git rev-list --count HEAD`), plus the
repository variable `TESTFLIGHT_BUILD_OFFSET` when it is set.

- The number only rises, because `main` only moves forward: it is
  fast-forwarded to commits the branch built.
- One commit always gets the same number, so a build names its commit. What
  to Test and the run's Summary print it, and `git rev-list --count <sha>`
  gives it back.
- A second upload of the same commit is refused as a duplicate rather than
  reaching the phone twice.
- It starts above anything uploaded by hand (the project's
  `CURRENT_PROJECT_VERSION` is 1). Main held 374 commits today, so the first
  build will be numbered about 380.
- The run number would restart at 1 and count re-runs of the same commit.

`manageAppVersionAndBuildNumber` is off. Left on (the default), Xcode quietly
renumbers a build whose number is taken, and nobody can then say which commit
is on the phone (Apple forum 693862 [live]). A clash is instead a red run
naming the fix.

`MARKETING_VERSION` stays the project's, 0.1.0, so every build sits under
0.1.0 in TestFlight until the project changes it. If main's history is ever
rewritten shorter, or a build is uploaded by hand, go to **Settings** →
**Secrets and variables** → **Actions** → **Variables** tab → **New
repository variable**, name `TESTFLIGHT_BUILD_OFFSET`, value `1000` (or any
number that clears the highest build in TestFlight).

---

## 5. Xcode and the runner

**Apple's floor.** Since 2026-04-28, App Store Connect takes only builds made
with Xcode 26 or later and the iOS 26 SDK [live: Apple's news]. It refuses any
build from a beta Xcode ("Unsupported SDK or Xcode version", a pipeline's
fifth red run [live]).

**What the image has** [live: runner-images, image 20260907]. `macos-15`
defaults to Xcode 16.4, which `build.yml` compiles and photographs with, and
carries 26.0.1, 26.1.1, 26.2 and 26.3 beside it. The workflow takes the
newest release Xcode of 26 or later: 26.3 with the iOS 26.2 SDK today.

- It skips beta installs (named like `Xcode_27_beta_3.app`, only on the
  `xcode-27` preview image) and the image's symlinked aliases.
- The repository variable `TESTFLIGHT_XCODE` (for example `26.2`) pins one
  version instead.
- `macos-26` defaults to Xcode 26.6 and gets new Xcodes first. When
  `macos-15` falls behind Apple's next floor (the Xcode 27 SDK, likely from
  spring 2027), change `runs-on` to `macos-26`: one line.

**This is the first Release compile and the first Xcode 26 compile in CI.**

- `build.yml` builds Debug with Xcode 16.4.
- Release-only code: five `#else` branches of `#if DEBUG`. All are trivial,
  and no DEBUG-only declaration is used outside one (checked by a scan here).
- Swift 6.2's type checker gives up on some expressions Xcode 16 solves: the
  owner's own build of 2026-09-23 failed on the summon charge's `ZStack`.
  Such a failure turns this job red with
  `…swift:line:col: error: the compiler is unable to type-check this
  expression in reasonable time`. The fix is to split that expression;
  `build.yml`'s list of slow expressions shows the candidates.
- Moving `build.yml` itself to Xcode 26.3 would catch these a step earlier.
  That is a separate decision; it would change every CI frame.

**Liquid Glass.** An app built with the iOS 26 SDK draws system controls
(sheets, alerts, menus) in iOS 26's style. The TestFlight build looks like the
owner's own Xcode 26 builds, not like CI's Xcode 16 frames.

---

## 6. What the phone gets

- **The Release build:** optimised, with no `-tour` and More → Diagnostics
  the plain console. It installs over the build from Xcode, keeping the save.
- **Sign in with Apple:** the same Apple user id as before (it belongs to
  the team), so the same account key and save file.
- **iCloud:** the **Production** database (step 5). The cloud copy starts
  fresh there, and the Allies screen reads Production.
- **Supabase:** the same project and the same rows; nothing depends on the
  build type.
- **In-app purchases:** Apple's sandbox, charging nothing. They load only
  once the products and the Paid Apps agreement of `Docs/STORE.md` §8 exist.
- **Export compliance:** `ITSAppUsesNonExemptEncryption` = NO is committed
  (b60dd12), so builds do not wait for the encryption question.
- **Lifetime:** each build lasts 90 days in TestFlight.

---

## 7. When a run is red

The job prints why at the end of its log and in the run's Summary. Read the
failing step's lines first.

| The run says | Why | Do this |
|---|---|---|
| *Notice:* TestFlight is not set up yet (grey, not red) | A secret is missing | §1 step 12 |
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `APPLE_TEAM_ID` / `ASC_KEY_P8` should be… | That paste is wrong | Settings → Secrets → that secret → **Update**, paste again |
| Archive: `….swift:12:5: error: the compiler is unable to type-check this expression in reasonable time` | Xcode 26's type checker (§5) | Split the expression, push, fast-forward main |
| Archive: another Swift error | Release or Swift 6.2 differs from `build.yml`'s Debug on Xcode 16 | Fix the code as for a red `build.yml` |
| Check the archive: *Entitlement lost* | The ad-hoc signature lacks a key of the entitlements file | Tell Claude; the step prints what was signed |
| Check the archive: *The app is over 4 GB* | §8 | §8 |
| Export: *Cloud signing permission error* / *You haven't been given access to cloud-managed distribution certificates* | The key is not Admin | Steps 8–10 with Access **Admin**; update `ASC_KEY_ID` and `ASC_KEY_P8`; revoke the old key |
| Export: *No suitable application records were found* | No app record | Step 6 |
| Export: *Provisioning profile … doesn't include the …applesignin / icloud… entitlement*, or *doesn't support the iCloud.com.pantheon.game container* | The App ID lacks a capability | Steps 3–4, then **Re-run jobs** |
| Export: *maximum number of certificates* | The team already has its limit of Apple Distribution certificates, and the first export makes a cloud-managed one | developer.apple.com → Certificates → revoke one you no longer use |
| Export: *Program License Agreement* / *PLA Update available* | Apple published a new agreement | Accept it at developer.apple.com/account |
| Export: *Build N is already on App Store Connect* | This commit was uploaded before (a re-run), or the number was taken by hand | Nothing for a re-run; otherwise set `TESTFLIGHT_BUILD_OFFSET` (§4) |
| Export: *Unsupported SDK or Xcode version* | A beta Xcode was chosen | Set `TESTFLIGHT_XCODE` to a release |
| *No space left on device* | A lean image | Tell Claude: raise the 12 GB threshold of *Make room on the disk* |
| Wait for TestFlight: *App Store Connect refused build N* | Processing ended INVALID | Apple's email to the Account Holder names an ITMS code; give Claude the code |
| Wait for TestFlight: *No internal testing group* (warning) | Steps 14–15 not done | Steps 14–15 |
| Wait for TestFlight: *waits for export compliance* (warning) | `ITSAppUsesNonExemptEncryption` is missing from the build | Answer on the build's page, or restore the build setting |

**Re-run jobs** on a red run reuses its commit and number, which is right
until the upload has succeeded. A run whose upload was accepted but whose
wait failed only needs its third job re-run.

---

## 8. The app's size

Pantheon.app is about 3.1 GB. Its resources are 3.07 GB: 2.80 GB of models,
0.24 GB of portraits, and the rest stage, audio and fonts (measured here
today). App Store Connect refuses an app over **4 GB uncompressed** [live:
Apple's *Maximum build file sizes*]. Each run prints the size and its share
of the limit, warns at 90% and stops at 100%. Remakes at the hero budgets
grow the models with every family.

The ways past the limit, when it comes near:

- **On-Demand Resources:** tagged asset packs hosted by Apple and downloaded
  when a screen needs them.
- **Background Assets:** Apple-hosted packs downloaded in the background.

Either is real engineering work across the model loader; neither is needed
yet. Separately, a download over 200 MB asks for Wi-Fi unless the phone
allows large downloads on cellular (**Settings → App Store → App
Downloads**) [recall].

The runner holds the app about four times over: a 6 GB checkout, then the
installed app and the archive, then a re-signed copy and the `.ipa`. GitHub
promises only 14 GB free on a macOS runner [live, via a search engine]; images
have shipped with 18 GB and with 57 GB [live: runner-images #10511]. So the
workflow:

- clears Xcode's compile products and the checkout's resources before the
  export;
- removes older Xcodes, oldest first, when the checkout leaves under 12 GB;
- prints the free space at each stage.

---

## 9. The key's safety

The Admin key can do anything in App Store Connect.

- It lives in GitHub's encrypted secrets. The workflow writes it to the
  runner's temp folder only for the jobs that need it, readable by the job's
  user alone, and deletes it in a step that runs even after a failure.
- Nothing prints it. This repository is **public**, so its Actions logs are
  public too. The failure explainer drops any line carrying a token before
  printing Xcode's distribution log.
- Only people with write access can start the workflow, and nothing gives a
  fork's pull request the secrets (there is no `pull_request` trigger).

To replace the key (or at once, if the `.p8` ever leaks):

1. App Store Connect → **Users and Access** → **Integrations** → **Team
   Keys** → the key → **Revoke**.
2. Make a new one (§1 steps 8–10).
3. Update `ASC_KEY_ID` and `ASC_KEY_P8`.

Standard GitHub runners are free for a public repository. If the repository
ever goes private, macOS minutes are billed (`build.yml`'s header has the
rate), about 30 of them per upload.

---

## 10. What was checked here, and what cannot be

There is no Mac or Xcode in this environment, so the workflow has never run.
What was verified here:

- `actionlint` 1.7.12 with `shellcheck` 0.11.0 on the whole workflow: clean.
  The YAML and the plist parse.
- The waiting job's Python ran against a mock App Store Connect in five
  scenarios: processed with and without an existing What to Test, no
  internal group, refused, and never processed. Every call's token was
  verified with PyJWT against a fresh P-256 key.
- 2,000 tokens were verified, 18 of them with a short `r` or `s`, to prove
  the signature conversion.
- The setup check ran against seven secret configurations, including a
  base64 `.p8` and Windows line endings. It never prints key material.
- The What-to-Test and build-number steps ran on this repository's history.
- The Xcode chooser, the entitlement assertion, the archive's retry and the
  export's error handling ran on a Linux simulation with stubbed `xcodebuild`
  and `PlistBuddy`.
- Every App Store Connect endpoint, field and enum the job uses was read off
  Apple's reference: `/apps`, `/builds` (`filter[version]`,
  `sort=-uploadedDate`, `processingState`), `betaBuildLocalizations`,
  `betaGroups` (`isInternalGroup`, `hasAccessToAllBuilds`) and
  `buildBetaDetail` (`internalBuildState`). The token format came from
  *Generating tokens for API requests* [live].

What only the first real run can prove:

- That Apple accepts the ad-hoc archive for this project. Xcode Cloud's
  recipe and several pipelines say it will, and the retry covers the manual
  style.
- That the Release build compiles under Xcode 26.3.
- The export's exact error wording, which only shapes the messages.
- Whether `DistributionSummary.plist` is written on an upload; it is printed
  if it is.

Sources:

- **Apple:** App Store Connect Help (*Add a new app*, *Add internal testers*,
  *App Store Connect API*, *Maximum build file sizes*), *Creating API keys*,
  *Generating tokens*, *Upcoming SDK minimum requirements*, TN3192, *Enable
  app capabilities*, *Register an App ID*.
- **Apple Developer Forums:** threads 720887, 756119, 760819, 776036,
  693862.
- **GitHub:** actions/runner-images READMEs (macos-15, macos-26),
  issues #10511 and #14404, actions/checkout's source, and community
  discussion 169535.
- **Public pipelines:** bitrise-steplib/steps-xcode-archive #278,
  hideoutgames/zremote #64, lrandazzo1/MFFU #65, kipyin/eloquent #34, and
  the workflows of iragm/fishauctions-app, bounce12340/work-schedule,
  lockdown-systems/cyd-mobile, yasyf/cc-present and Chorus-ACE/Greatdori.
