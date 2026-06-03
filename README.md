## Studio Git Orchestrator

---

#### Overview

In modern AI engineering, seamlessly transitioning between local development environments, cloud workspaces (like Google AI Studio), and version-controlled repositories can introduce significant friction.

**The Studio Git Orchestrator** is an automated, enterprise-grade Bash utility designed to eliminate this friction. It provides a secure, interactive terminal interface that handles Python virtual environment scaffolding, GitHub repository provisioning, and AI-assisted commit generation, transforming complex DevSecOps workflows into a single keystroke.

---

#### Core Capabilities

#### 1. Secure Workspace Scaffolding
Standard tutorials often instruct developers to place the Python virtual environment **`(venv)`** inside their Git repository, creating security risks and bloated commits. This tool enforces an inverted, highly secure topology:

* The **`venv/`** is generated as the Parent directory.
* The **`src/`** **(containing the `.git/` repository)** is generated as the Child directory.
* **Result:** Git remains completely physically isolated from your Python binaries, permanently preventing accidental tracking of massive dependency libraries.

#### 2. Automated GitHub Provisioning
The orchestrator bypasses the GitHub web interface entirely. Utilizing the GitHub REST API, it dynamically verifies if your target repository exists in the cloud. If it detects a **`404 Not Found`**, the utility automatically provisions a new, private GitHub repository on the fly and securely links it to your local environment.

#### 3. AI-Assisted Version Control (Google Gemini)
The orchestrator natively integrates with the **Google AI Studio Developer API (Gemini 1.5 Flash)** to automate the most tedious aspects of version control:

* **Auto-Documentation:** If a project lacks a **`README.md`**, the engine analyzes your local directory tree, feeds the structure to Gemini, and automatically generates a professional, context-aware project summary.
* **Auto-Committing:** Before synchronizing your code with GitHub, the engine extracts your exact code changes **`(git diff)`**, pipes them to the AI, and generates a strict, highly accurate Conventional Commit message based purely on your work.

---
#### Installation & Configuration

> ⚠️ **SECURITY NOTICE:** To maintain absolute Zero-Trust security, you must never commit your active credentials to a repository. The active bash script utilizing Personal Access Tokens is explicitly ignored via `.gitignore`. The file provided in this repository **`(orchestrator.template.sh)`** is a sanitized blueprint.

#### Step 1: Prepare the Executable
* Clone or download this repository to your machine.
* Duplicate the template file to create your active, local executable:

```bash
cp orchestrator.template.sh orchestrator.sh
```

* Make the new script executable by your operating system:

```bash
chmod +x orchestrator.sh
```

#### Step 2: Inject Your Credentials
Open **`orchestrator.sh`** in any text editor. At the very top of the file **(under the CONFIGURATION MATRIX section)**, you must provide your specific credentials:

1. **GITHUB_USER:** Your exact GitHub username.
2. **GITHUB_EMAIL:** The email address associated with your GitHub account.
3. **GITHUB_TOKEN:** A GitHub `Personal Access Token (PAT)`.
    * **How to get this:** Go to GitHub.com -> Settings -> Developer Settings -> Personal access tokens (classic). Generate a new token and ensure the repo scope checkbox is fully checked.
4. **GEMINI_API_KEY:** Your Google AI Studio token.
    * **How to get this:** Go to Google AI Studio and click **`"Create API key"`**.
5. **DEV_BASE_DIR:** The absolute path to the folder on your computer where you want your projects saved **`(e.g., /home/username/Documents/Projects)`**.

---

#### Operational Walkthrough

Once configured, simply run the script from your terminal:

```bash
./orchestrator.sh
```

You will be presented with a strict, interactive 3-tier menu matrix. Type the number corresponding to the action you wish to perform and press Enter.

#### Protocol 1: Initialize New Workspace
Best used when starting a brand new AI project from scratch.

* **What it does:** Asks you for a project name. It creates the secure directory structure, builds the Python virtual environment, initializes Git, creates a default **`.gitignore`** and **`README.md`**, provisions the remote repository on GitHub, pushes the initial setup to the cloud, and drops you directly into an activated Python terminal ready to code.

#### Protocol 2: Execute Automated Sync
Best used when you have finished coding and want to save your work to GitHub.

* **What it does:** Must be run from inside your project folder. It stages all your saved changes, queries the Gemini API to write a professional commit message summarizing your work, and securely pushes the code to GitHub. If the remote repository doesn't exist yet, it will create it for you.

#### Protocol 3: Clone Existing Remote Repository
Best used when you are moving to a new computer or downloading an existing project.

* **What it does:** Asks you for the name of a repository you already own on GitHub. It securely authenticates using your embedded token, downloads the repository to your defined **`DEV_BASE_DIR`**, and ensures it is ready for immediate development.