## Studio Git Orchestrator

---

#### Overview

In modern AI engineering, seamlessly transitioning between local development environments, ephemeral cloud workspaces (like Google Cloud Shell or AI Studio), and version-controlled repositories — especially across **multiple GitHub identities** — can introduce significant friction and dangerous human-error vectors.

**The Studio Git Orchestrator** is an automated, enterprise-grade Bash utility designed to eliminate this friction entirely. It provides a secure, interactive terminal interface that handles Python virtual environment scaffolding, GitHub repository provisioning, AI-assisted commit generation, and explicit multi-account identity routing — transforming complex DevSecOps workflows into a single keystroke while making catastrophic misroutes structurally impossible.

---

#### Core Capabilities

#### 1. Secure Workspace Scaffolding
Standard tutorials often instruct developers to place the Python virtual environment **`(venv)`** inside their Git repository, creating security risks and bloated commits. This tool enforces an inverted, highly secure topology:

* The **`venv/`** is generated as the Parent directory.
* The **`src/`** **(containing the `.git/` repository)** is generated as the Child directory.
* **Result:** Git remains completely physically isolated from your Python binaries, permanently preventing accidental tracking of massive dependency libraries.

#### 2. Universal Identity Gate (Multi-Account Routing)
The orchestrator solves one of the most dangerous failure modes in multi-account Git workflows: **pushing code to the wrong GitHub account**. The Identity Gate operates as a two-stage explicit confirmation pipeline:

* **Auto-Detection Seed:** A hostname check seeds the default account identity (e.g., work machine defaults to the work account).
* **Visual Confirmation Banner:** A Unicode box-drawing card displays the staged identity (hostname, account, email) before any destructive operation.
* **Explicit Pivot Path:** If the auto-detected identity is wrong, the script gracefully offers to switch to the alternate account — no source code editing required.
* **Final Override Lock:** Manual overrides require a secondary confirmation, eliminating muscle-memory disasters.

#### 3. Automated GitHub Provisioning
The orchestrator bypasses the GitHub web interface entirely. Utilizing the GitHub REST API, it dynamically verifies if your target repository exists in the cloud. If it detects a **`404 Not Found`**, the utility automatically provisions a new, private GitHub repository on the fly and securely links it to your local environment.

#### 4. AI-Assisted Version Control (Google Gemini)
The orchestrator natively integrates with the **Google AI Studio Developer API (Gemini 1.5 Flash)** to automate the most tedious aspects of version control:

* **Auto-Documentation:** If a project lacks a **`README.md`**, the engine analyzes your local directory tree, feeds the structure to Gemini, and automatically generates a professional, context-aware project summary.
* **Auto-Committing:** Before synchronizing your code with GitHub, the engine extracts your exact code changes **`(git diff)`**, pipes them to the AI, and generates a strict, highly accurate Conventional Commit message based purely on your work.

#### 5. Operational Resilience
Designed for ephemeral environments (Cloud Shell, Chromeboxes, transient VMs) where sessions can terminate without warning:

* **Extended Signal Trapping:** Catches `SIGINT`, `SIGTERM`, and `SIGHUP` to gracefully recover from keyboard interrupts, kill signals, and terminal hangups.
* **Mid-Merge State Recovery:** Automatically detects and remediates partial-merge artifacts (`MERGE_HEAD`, stale `index.lock` files) left behind by interrupted Git operations.
* **Strict Error Halting:** `set -e` prevents cascade failures across operations.
* **Format Validation:** Repository names are validated against enterprise naming conventions before submission to GitHub.

#### 6. Manjaro-Inspired Terminal Aesthetic
The interface adopts a clean cyan + lime green color palette inspired by the Manjaro Linux terminal aesthetic, with Unicode box-drawing characters for visually-aligned status panels and banners.

---

#### Installation & Configuration

> ⚠️ **SECURITY NOTICE:** To maintain absolute Zero-Trust security, you must never commit your active credentials to a repository. The active bash script utilizing Personal Access Tokens is explicitly ignored via `.gitignore`. The file provided in this repository **`(orchestrator.template.sh)`** is a sanitized blueprint.

#### Step 1: Prepare the Executable
* Clone or download this repository to your machine.
* Duplicate the template file to create your active, local executable:

```bash
cp orchestrator.template.sh orchestrator.sh
```

* Add the operational file to .gitignore immediately to prevent accidental credential exposure:

```bash
echo "orchestrator.sh" >> .gitignore
```

Make the new script executable by your operating system:

```bash
chmod +x orchestrator.sh
```

##### Step 2: Inject Your Credentials
Open **`orchestrator.sh`** in any text editor. At the very top of the file **(under the CONFIGURATION MATRIX section)**, you will find a hostname-based **`if/else`** block defining **two complete identity pairs:** a default account and an alternate account.

Populate the following fields for both identity pairs:

1. **`DEFAULT_GITHUB_USER / ALT_GITHUB_USER:`** Your exact GitHub usernames.
2. **`DEFAULT_GITHUB_EMAIL / ALT_GITHUB_EMAIL:`** The email addresses associated with each GitHub account.
3. **`DEFAULT_GITHUB_TOKEN / ALT_GITHUB_TOKEN:`** GitHub Personal Access Tokens (PAT) for each account.
    * How to get this: Go to GitHub.com → Settings → Developer Settings → Personal access tokens (classic). Generate a new token and ensure the repo scope checkbox is fully checked.
4. GEMINI_API_KEY: Your Google AI Studio token.
    * How to get this: Go to Google AI Studio and click "Create API key".
5. DEV_BASE_DIR: The absolute path to the folder on your computer where you want your projects saved (e.g., /home/username/Development).

#### Step 3: Configure Hostname Auto-Detection
Replace the **`INSERT_HOME_HOSTNAME_HERE`** placeholder with the output of:

```bash
hostname
```

This tells the script which machine corresponds to which default account — when you run from this hostname, the DEFAULT identity pair activates; from any other machine, the ALT pair becomes the default. The Identity Gate always offers a pivot regardless of which one auto-loads.

#### Step 4: Verify Redaction Hygiene (Recommended)
Before committing any updates to this repository, scan for accidentally leaked secrets:

```bash
grep -E "(ghp_[A-Za-z0-9]{30,}|AIzaSy[A-Za-z0-9_-]{30,})" orchestrator.template.sh
```

A clean output (zero matches) confirms the template is safe to publish.

---

#### Operational Walkthrough
Once configured, simply run the script from your terminal:

```bash
./orchestrator.sh
```

You will be presented with a strict, interactive 4-protocol menu matrix. Type the number corresponding to the action you wish to perform and press Enter. Every protocol begins by invoking the Universal Identity Gate, ensuring you always know which GitHub account is about to receive your work.

##### Protocol 1: Initialize New Workspace
Best used when starting a brand new AI project from scratch.

* **What it does:** Asks you for a project name. It creates the secure directory structure, builds the Python virtual environment, initializes Git, creates a default **`.gitignore`** and **`README.md`**, provisions the remote repository on GitHub, pushes the initial setup to the cloud, and drops you directly into an activated Python terminal ready to code.

##### Protocol 2: Execute Automated Sync
Best used when you have finished coding and want to save your work to GitHub.

* **What it does:** Must be run from inside your project folder. It stages all your saved changes, queries the Gemini API to write a professional commit message summarizing your work, and securely pushes the code to GitHub. If the remote repository doesn't exist yet, it will create it for you.

##### Protocol 3: Clone Existing Remote Repository
Best used when you are moving to a new computer or downloading an existing project.

* **What it does:** Lists all repositories (public and private) owned by the currently-selected identity, presents them in a numbered selection panel, and securely clones the chosen repository to your defined DEV_BASE_DIR — ready for immediate development.

##### Protocol 4: Adopt Existing Directory
Best used when you have an existing local folder (with or without a .git/ history) and want to publish it to a specific GitHub account with full control over the destination.

* **What it does:** Smart-detects the state of your local directory and routes through the appropriate path:
    * **If a `.git/` folder exists:** Audits and displays the current remote URL, then asks whether to preserve the destination or redirect to a new one.
    * **If no `.git/` folder exists:** Initializes a fresh repository and routes to the Destination Picker.
* **Destination Picker offers two sub-paths:**
    * [ 1 ] Create a new repository with a custom name (with naming-convention validation).
    * [ 2 ] Push into an existing repository (with safe-merge or force-push strategy selection, including a typed OVERWRITE confirmation gate for destructive operations).
* **README handling:** If your local folder already has a README.md, it is preserved. If not, one is generated via Gemini.

---

#### Architectural Topology

```bash
PROJECT_ROOT/
├── orchestrator.template.sh    # Public, redacted blueprint (committed)
├── orchestrator.sh             # Operational file with credentials (gitignored)
├── .gitignore                  # Must contain 'orchestrator.sh'
└── README.md                   # This file
```

#### Dependencies
The script performs a pre-flight verification for the following system binaries:

* **curl —** HTTPS transport to GitHub and Gemini APIs
* **jq —** JSON parsing for API responses
* **git —** Version control operations
* **python3 —** Virtual environment provisioning

Missing dependencies are reported with install guidance on first run.

---

#### Security Posture

|          **Layer**          |                          **Mechanism**                          |
|:---------------------------:|:---------------------------------------------------------------:|
| Credential Isolation        | Operational script gitignored; only redacted template is public |
| Identity Verification       | Two-stage Identity Gate prevents wrong-account pushes           |
| Destructive Op Confirmation | Force-push requires typed OVERWRITE phrase                      |
| Signal Robustness           | SIGINT / SIGTERM / SIGHUP handled gracefully                    |
| Merge State Recovery        | Automatic cleanup of interrupted Git operations                 |
| Format Validation           | Repo names validated against ^[ a-z0-9 ]+(-[ a-z0-9 ]+)*$       |
| HTTP Error Discrimination   | Distinct handling for 401 / 403 / 404 / 5xx responses           |
| Strict Mode                 | set -e halts on any command failure                             |

---

#### License
Distributed for educational and personal use. Adapt freely; attribution appreciated.