# Install CameraIMU on iPhone (without Xcode locally)

## Overview

Since Xcode only runs on macOS, we use **GitHub Actions** (free macOS runner) to compile the project in the cloud, then sideload the resulting `.ipa` to your iPhone from a Linux desktop.

```
Linux: push code to GitHub
        → GitHub Actions: compile on macOS runner
        → Download .ipa artifact
        → Sideload to iPhone via AltServer-Linux
```

---

## Step 1: Push Project to GitHub

```bash
cd CameraIMU/
git init
git add -A
git commit -m "initial commit"
```

Create a new repo on [github.com](https://github.com/new), then:

```bash
git remote add origin git@github.com:<YOUR_USERNAME>/CameraIMU.git
git push -u origin main
```

This will automatically trigger the GitHub Actions build (see `.github/workflows/build.yml`).

---

## Step 2: Download the .ipa

1. Go to your repo on GitHub
2. Click the **Actions** tab
3. Click the latest **Build IPA** workflow run
4. Under **Artifacts**, download `CameraIMU-unsigned`
5. Unzip it — you'll get `CameraIMU.ipa`

---

## Step 3: Sideload to iPhone from Linux

### Option A: AltServer-Linux (recommended)

[AltServer-Linux](https://github.com/NyaMisty/AltServer-Linux) is an open-source tool that signs and installs `.ipa` files using your Apple ID.

#### Install dependencies

```bash
# Ubuntu/Debian
sudo apt install libavahi-compat-libdnssd-dev usbmuxd
```

#### Install AltServer-Linux

Download the latest release from:
https://github.com/NyaMisty/AltServer-Linux/releases

```bash
chmod +x AltServer
```

#### Install the app

1. Connect your iPhone to the Linux machine via USB
2. Trust the computer on your iPhone if prompted
3. Run:

```bash
./AltServer -u <IPHONE_UDID> -a <YOUR_APPLE_ID> -p <YOUR_PASSWORD> CameraIMU.ipa
```

To find your iPhone's UDID:

```bash
idevice_id -l
```

(Requires `libimobiledevice-utils`: `sudo apt install libimobiledevice-utils`)

### Option B: Sideloadly

[Sideloadly](https://sideloadly.io/) has a Linux version with a GUI. Download it, open the `.ipa`, enter your Apple ID, and click Start.

---

## Step 4: Trust the Developer Certificate on iPhone

After installation:

1. Open **Settings** on your iPhone
2. Go to **General → VPN & Device Management**
3. Tap your Apple ID under "Developer App"
4. Tap **Trust**

---

## Notes

- Free Apple ID signing is valid for **7 days**. After expiration, re-sideload the `.ipa`.
- A paid Apple Developer account ($99/year) extends this to 1 year.
- The app requires a **physical iPhone** — camera and IMU sensors do not work in the simulator.
- If you have access to a Mac with Xcode, you can simply open `CameraIMU.xcodeproj`, connect your iPhone, and hit Run.
