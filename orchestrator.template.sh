#!/bin/bash
# ==============================================================================
# STUDIO GIT ORCHESTRATOR
# ==============================================================================
# This utility provides an automated, stable bridge between local/cloud AI
# environments and GitHub. It manages Python virtual environment scaffolding,
# Gemini-assisted commit generation, and dynamic repository provisioning.
#
# SECURITY NOTICE:
# Ensure 'orchestrator.sh' is added to your .gitignore to prevent the accidental
# commitment of the Personal Access Tokens configured below.
# ==============================================================================

# ------------------------------------------------------------------------------
# ENFORCE STRICT ERROR HANDLING
# ------------------------------------------------------------------------------
# Instructs the system to halt the script immediately if any command fails.
# This prevents errors from snowballing (e.g., preventing a push if setup fails).
set -e

# ==============================================================================
# 1. CONFIGURATION MATRIX & CREDENTIALS
# ==============================================================================
# These variables act as the localized Service Account for the CLI operations.
# The user must populate these with their specific account details.

GITHUB_USER="XXXXX"                 # <-- Replace with GitHub Username
GITHUB_EMAIL="XXXXX"                # <-- Replace with Email Address
GITHUB_TOKEN="XXXXX"                # <-- Replace with GitHub PAT ('repo' scope)

# ------------------------------------------------------------------------------
# GOOGLE AI STUDIO CREDENTIALS
# Generate this key at: https://aistudio.google.com/app/apikey
# ------------------------------------------------------------------------------
GEMINI_API_KEY="XXXXX"              # <-- Replace with Google AI Studio API Key

# The absolute path on your computer where the script will create or download projects.
DEV_BASE_DIR="/home/{USERNAME}/Development"     # <-- Replace with target working directory

# ------------------------------------------------------------------------------
# TERMINAL AESTHETICS (ANSI Escape Codes)
# ------------------------------------------------------------------------------
# Used to apply colors to the terminal output for readability and severity tracking.
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[1;35m'
NC='\033[0m'

# ==============================================================================
# SAFETY PROTOCOLS
# ==============================================================================
# Catches manual user termination (Ctrl+C). Instead of breaking the terminal,
# it gracefully stops the process and cleans up the environment.
function handle_keyboard_interrupt() {
    echo -e "\n\n${RED}[ERROR] Operational Exception: Keyboard Interrupt sequence intercepted.${NC}"
    echo -e "${PURPLE}[INFO] Decoupling workflows and cleaning up the terminal...${NC}\n"
    exit 130
}
trap handle_keyboard_interrupt SIGINT

# ==============================================================================
# PRE-FLIGHT DEPENDENCY VERIFICATION
# ==============================================================================
# Checks the user's computer to ensure all required software tools are installed
# before attempting to run complex cloud operations.
function verify_system_dependencies() {
    local missing_deps=()
    for binary in curl jq git python3; do
        if ! command -v "$binary" &> /dev/null; then
            missing_deps+=("$binary")
        fi
    done

    # If tools are missing, it halts and provides the command to install them.
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}[ERROR] Structural failure: Missing required system binaries: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}[WARNING] Please run: sudo apt update && sudo apt install -y ${missing_deps[*]} (or equivalent)${NC}"
        exit 1
    fi
}

# Execute the check immediately upon starting the script.
verify_system_dependencies

# ==============================================================================
# 2. GITHUB API PROVISIONING ENGINE
# ==============================================================================
# This function communicates directly with GitHub to check if a repository exists.
# If it does not exist, it offers to create it automatically.
function ensure_github_repo_exists() {
    # An infinite loop ensures that if the user makes a typo, they can retry
    # without having to restart the entire script.
    while true; do
        echo -e "${CYAN}[INFO] Validating remote repository status on GitHub: '$TARGET_REPO'...${NC}"

        # Ping GitHub to see if the repository is there. Extracts the HTTP Status Code.
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_USER/$TARGET_REPO") || {
            echo -e "${RED}[ERROR] curl invocation failed when contacting GitHub API.${NC}"
            exit 1
        }

        if [ "$HTTP_STATUS" == "404" ]; then
            # A 404 code means the repository does not exist on GitHub yet.
            echo -e "\n${YELLOW}[WARNING] Repository '$TARGET_REPO' not found under the provided GitHub account.${NC}"
            echo "Select a provisioning action:"
            echo "  c) Provision '$TARGET_REPO' as a new private repository."
            echo "  r) Retry with corrected repository name."
            echo "  a) Abort operation."
            echo ""
            read -p "Selection (c/r/a): " USER_CHOICE

            case $USER_CHOICE in
                c|C)
                    # Send a command to GitHub to create a new, private repository.
                    echo -e "${PURPLE}[INFO] Transmitting provisioning request to GitHub API...${NC}"
                    CREATE_RESP=$(curl -s -w "\n%{http_code}" -X POST \
                        -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        -d "{\"name\":\"$TARGET_REPO\", \"private\":true}" \
                        "https://api.github.com/user/repos") || {
                        echo -e "${RED}[ERROR] curl invocation failed when creating repository.${NC}"
                        exit 1
                    }

                    CREATE_STATUS=$(echo "$CREATE_RESP" | tail -n1)
                    if [ "$CREATE_STATUS" == "201" ]; then
                        echo -e "${GREEN}[SUCCESS] Remote repository '$TARGET_REPO' successfully provisioned.${NC}"
                        break # Exit the loop, the repository is ready.
                    else
                        echo -e "${RED}[ERROR] Provisioning failed. GitHub API returned HTTP $CREATE_STATUS.${NC}"
                        exit 1
                    fi
                    ;;
                r|R)
                    # Allows the user to fix a typo and try the check again.
                    read -p "Enter corrected repository name: " CORRECTED_NAME
                    if [ -n "$CORRECTED_NAME" ]; then
                        TARGET_REPO="$CORRECTED_NAME"
                    fi
                    ;;
                a|A)
                    echo -e "${RED}[ABORT] Operation terminated by user.${NC}"
                    exit 1
                    ;;
                *)
                    echo -e "${RED}[ERROR] Invalid selection. Aborting.${NC}"
                    exit 1
                    ;;
            esac

        elif [ "$HTTP_STATUS" == "200" ]; then
            # A 200 code means the repository was found successfully.
            echo -e "${GREEN}[SUCCESS] Remote repository verified.${NC}"
            break
        elif [ "$HTTP_STATUS" == "401" ] || [ "$HTTP_STATUS" == "403" ]; then
            # Authentication / authorization failure — typically a bad or expired PAT.
            echo -e "${RED}[ERROR] GitHub authentication rejected (HTTP $HTTP_STATUS).${NC}"
            echo -e "${YELLOW}[WARNING] Verify your Personal Access Token is valid and has 'repo' scope.${NC}"
            exit 1
        else
            echo -e "${RED}[ERROR] GitHub API returned unexpected status code: $HTTP_STATUS${NC}"
            exit 1
        fi
    done
}

# ==============================================================================
# 3. OPERATIONAL MENU ROUTER
# ==============================================================================
# Provides the primary user interface for selecting workflow pipelines.
echo -e "${CYAN}=================================================================================${NC}"
echo -e "${CYAN}                          STUDIO GIT ORCHESTRATOR${NC}"
echo -e "${CYAN}=================================================================================${NC}"
echo ""
echo -e "${PURPLE}Select an operational protocol:${NC}"
echo "  1) Initialize New Workspace (VENV + Git + GitHub Sync)"
echo "  2) Execute Automated Sync (AI Commits & GitHub Push)"
echo "  3) Clone Existing Remote Repository"
echo ""
read -p "Protocol Selection [1] [2] [3]: " PROTOCOL

case $PROTOCOL in
    # ==============================================================================
    # PROTOCOL 1: WORKSPACE INITIALIZATION
    # ==============================================================================
    # Creates a secure folder structure. It builds an isolated Python environment,
    # initializes version control, and connects the local folder to the cloud.
    1|01)
        echo -e "\n${CYAN}[INFO] Initiating workspace scaffolding sequence.${NC}"
        read -p "Enter target workspace name: " PROJECT_NAME

        TARGET_REPO="$PROJECT_NAME"
        TARGET_DIR="$DEV_BASE_DIR/$PROJECT_NAME"
        SRC_DIR="$TARGET_DIR/src"

        # Pre-flight check to prevent overwriting existing folders on the computer.
        if [ -d "$TARGET_DIR" ]; then
            echo -e "${RED}[ERROR] Target directory '$TARGET_DIR' already exists. Aborting to prevent data loss.${NC}"
            exit 1
        fi

        # Creates an isolated Python space so dependencies don't conflict with other projects.
        echo -e "${PURPLE}[INFO] Provisioning Python Virtual Environment at $TARGET_DIR...${NC}"
        python3 -m venv "$TARGET_DIR"

        # Creates the dedicated source code folder inside the environment.
        echo -e "${PURPLE}[INFO] Initializing source directory structure...${NC}"
        mkdir -p "$SRC_DIR"
        cd "$SRC_DIR"

        # Asks GitHub if this project name already exists in the cloud.
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_USER/$TARGET_REPO") || {
            echo -e "${RED}[ERROR] curl invocation failed when contacting GitHub API.${NC}"
            exit 1
        }

        if [ "$HTTP_STATUS" == "200" ]; then
            echo ""
            echo -e "${YELLOW}[WARNING] Repository '$TARGET_REPO' detected in the cloud vault.${NC}"
            read -p "Initialize local workspace and clone remote data? [y/n]: " USER_RESPONSE

            case $USER_RESPONSE in
                y|Y)
                    # If the user says yes, it downloads the existing cloud code into the local folder.
                    echo -e "${PURPLE}[INFO] Cloning remote repository...${NC}"
                    AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
                    git clone "$AUTH_REPO_URL" .

                    git config user.name "$GITHUB_USER"
                    git config user.email "$GITHUB_EMAIL"

                    # Activates the Python environment to install necessary packages.
                    echo -e "${PURPLE}[INFO] Restoring Python dependencies...${NC}"
                    source "$TARGET_DIR/bin/activate"

                    if [ -f requirements.txt ]; then
                        echo -e "${PURPLE}[INFO] requirements.txt detected. Executing installation...${NC}"
                        pip install --upgrade pip
                        pip install -r requirements.txt
                        echo -e "${GREEN}[SUCCESS] Dependencies restored.${NC}"
                    else
                        echo -e "${YELLOW}[WARNING] No requirements.txt found. Dependency sync skipped.${NC}"
                    fi
                    ;;
                *)
                    echo -e "${PURPLE}[INFO] Operation aborted by user.${NC}"
                    exit 0
                    ;;
            esac

        elif [ "$HTTP_STATUS" == "401" ] || [ "$HTTP_STATUS" == "403" ]; then
            # Authentication / authorization failure — typically a bad or expired PAT.
            echo -e "${RED}[ERROR] GitHub authentication rejected (HTTP $HTTP_STATUS).${NC}"
            echo -e "${YELLOW}[WARNING] Verify your Personal Access Token is valid and has 'repo' scope.${NC}"
            exit 1
        else
            # If the cloud repository does not exist (404 or other), it builds a brand new local project.
            echo -e "${PURPLE}[INFO] Repository not found in cloud. Initializing fresh workspace...${NC}"
            git init
            git config user.name "$GITHUB_USER"
            git config user.email "$GITHUB_EMAIL"
            git config --global init.defaultBranch main

            # Runs the function above to create the cloud repository automatically.
            ensure_github_repo_exists

            # Links the local folder to the new GitHub cloud repository.
            AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
            git remote add origin "$AUTH_REPO_URL"

            echo -e "${PURPLE}[INFO] Generating baseline security configurations and README.md...${NC}"
            echo "# AI Studio Workspace | $TARGET_REPO" > README.md
            echo "Workspace initialized via Studio Git Orchestrator." >> README.md

            # Tells Git to ignore sensitive files and massive Python cache folders.
            cat > .gitignore <<EOF
__pycache__/
.env
*.pyc
EOF

            # Packages the initial files and sends them to GitHub.
            source "$TARGET_DIR/bin/activate"
            git add .
            git commit -m "chore: initial workspace configuration and scaffolding"
            git branch -M main

            echo -e "${PURPLE}[INFO] Executing initial push to remote origin...${NC}"
            git push -u origin main
        fi

        echo ""
        echo -e "${GREEN}[SUCCESS] Workspace deployed successfully.${NC}"
        echo ""
        echo -e "${CYAN}[INFO] Activating virtual environment. Type 'exit' to terminate session.${NC}"

        # Automatically logs the user into their newly created, activated environment.
        exec bash --rcfile <(echo ". ~/.bashrc; source \"$TARGET_DIR/bin/activate\"")
        ;;

    # ==============================================================================
    # PROTOCOL 2: AUTOMATED SYNC (AI PIPELINE)
    # ==============================================================================
    # Stages local modifications, invokes the Google AI Studio Developer API to analyze
    # codebase changes, generates professional summaries, and synchronizes with GitHub.
    2|02)
        echo -e "\n${CYAN}[INFO] Initiating automated synchronization sequence.${NC}"

        # Verifies that the user is currently inside an active Git project.
        if [ ! -d ".git" ]; then
            echo -e "${RED}[ERROR] .git directory not found. Ensure you are executing from the project root.${NC}"
            exit 1
        fi

        echo -e "${PURPLE}[INFO] Injecting local tracking parameters...${NC}"
        git config user.name "$GITHUB_USER"
        git config user.email "$GITHUB_EMAIL"

        # Determines the name of the project by checking where the local Git connects to.
        if git config --get remote.origin.url > /dev/null 2>&1; then
            REPO_URL=$(git config --get remote.origin.url)
            TARGET_REPO=$(basename -s .git "$REPO_URL")
        else
            TARGET_REPO=${PWD##*/}
        fi

        ensure_github_repo_exists

        # Refreshes the secure connection link utilizing the embedded Personal Access Token.
        AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
        git remote remove origin 2>/dev/null || true
        git remote add origin "$AUTH_REPO_URL"

        # ----------------------------------------------------
        # AI DOCUMENTATION GENERATOR
        # ----------------------------------------------------
        # If the project is missing a README file, it asks Gemini to write one based on the files present.
        if [ ! -f "README.md" ]; then
            echo -e "${YELLOW}[WARNING] README.md not found. Initiating generation sequence.${NC}"
            if [ "$GEMINI_API_KEY" != "XXXXX" ]; then
                echo -e "${PURPLE}[INFO] Requesting AI-generated documentation via Google AI Studio API...${NC}"

                # Reads the names of all files in the directory to provide context to the AI.
                DIR_TREE=$(ls -1)

                README_PROMPT="You are an elite DevSecOps architect. Write a short, powerful, enterprise-grade description based on these files. Return ONLY the text, no markdown formatting or quotes. Files:"

                # Formats the request into a secure JSON structure required by Google AI Studio.
                PAYLOAD=$(jq -n --arg prompt "$README_PROMPT" --arg tree "$DIR_TREE" '{ contents: [{ parts: [{ text: ($prompt + "\n\n" + $tree) }] }] }')

                # Transmits the payload to the Gemini 1.5 Flash model and extracts the response.
                AI_DESC=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$GEMINI_API_KEY" -H "Content-Type: application/json" -d "$PAYLOAD" | jq -r '.candidates[0].content.parts[0].text')

                echo "# AI Studio Workspace | $TARGET_REPO" > README.md
                echo "$AI_DESC" >> README.md
                echo -e "${GREEN}[SUCCESS] Documentation generated and saved.${NC}"
            else
                # Fallback if the user has not configured their Gemini API key.
                echo -e "${PURPLE}[INFO] Applying standard documentation placeholder.${NC}"
                echo "# AI Studio Workspace" > README.md
                echo "An enterprise-grade software architecture." >> README.md
            fi
        fi

        # ----------------------------------------------------
        # STAGE & AI COMMIT GENERATION
        # ----------------------------------------------------
        echo -e "${PURPLE}[INFO] Staging modified assets...${NC}"
        git add .

        # Checks if any files were actually modified. If not, it halts to prevent empty pushes.
        if git diff --cached --quiet; then
            echo -e "${GREEN}[INFO] Working tree clean. No changes to commit.${NC}"
            exit 0
        fi

        COMMIT_MSG=""
        if [ "$GEMINI_API_KEY" != "XXXXX" ]; then
            echo -e "${PURPLE}[INFO] Requesting AI-generated Conventional Commit message via Google AI Studio API...${NC}"

            # Grabs a summary of the code changes (capped at 3000 chars to respect API limits).
            DIFF_PREVIEW=$(git diff --cached | head -c 3000)

            COMMIT_PROMPT="You are an elite version control AI. Read this git diff and write a single, concise Conventional Commit message (e.g. feat: added parsing module). Return ONLY the message string. Do not include markdown, quotes, or explanations. Diff:"
            PAYLOAD=$(jq -n --arg prompt "$COMMIT_PROMPT" --arg diff "$DIFF_PREVIEW" '{ contents: [{ parts: [{ text: ($prompt + "\n\n" + $diff) }] }] }')

            API_RESPONSE=$(curl -s -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$GEMINI_API_KEY" -H "Content-Type: application/json" -d "$PAYLOAD")
            COMMIT_MSG=$(echo "$API_RESPONSE" | jq -r '.candidates[0].content.parts[0].text' | tr -d '\n' | tr -d '"')
        fi

        # Fallback if the AI API is unreachable or fails to generate a response.
        if [ -z "$COMMIT_MSG" ] || [ "$COMMIT_MSG" == "null" ]; then
            COMMIT_MSG="Automated Push: $(date "+%Y-%m-%d %H:%M:%S") - Architecture sync"
        fi

        echo -e "${PURPLE}[INFO] Applying commit message: \"$COMMIT_MSG\"${NC}"
        git commit -m "$COMMIT_MSG"
        git branch -M main

        # ----------------------------------------------------
        # SECURE PUSH TO GITHUB
        # ----------------------------------------------------
        echo -e "${PURPLE}[INFO] Pushing payload to remote origin...${NC}"

        # Attempts to sync standardly. If GitHub rejects it (e.g., conflicting versions),
        # it executes a force push to ensure the cloud perfectly matches the local environment.
        if ! git push -u origin main > /dev/null 2>&1; then
            echo -e "${YELLOW}[WARNING] Fast-forward rejected. Executing force push to synchronize remote state...${NC}"
            git push -u origin main --force
        fi
        echo -e "${GREEN}[SUCCESS] Synchronization complete.${NC}"
        ;;

    # ==============================================================================
    # PROTOCOL 3: SECURE AUTOMATED PULL / CLONE
    # ==============================================================================
    # Retrieves an entire repository from GitHub and sets it up on the local machine.
    3|03)
        echo -e "\n${CYAN}[INFO] Initiating remote repository clone sequence.${NC}"
        echo -e "${PURPLE}[INFO] Compiling public repository mappings under account '$GITHUB_USER'...${NC}"

        # Queries the GitHub API to generate a list of all non-private repositories
        # owned by the configured user.
        mapfile -t REPO_LIST < <(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/users/$GITHUB_USER/repos?per_page=100" | jq -r '.[] | select(.private == false) | .name')

        if [ ${#REPO_LIST[@]} -eq 0 ]; then
            echo -e "${RED}[ERROR] Retrieval breakdown: Profile index returned empty or access was denied.${NC}"
            exit 1
        fi

        # Displays the retrieved repositories as an interactive numbered menu.
        echo -e "\n${CYAN}=================================================================================${NC}"
        echo -e "${CYAN}                       AVAILABLE REMOTE CLOUD TARGETS           ${NC}"
        echo -e "${CYAN}=================================================================================${NC}"
        for i in "${!REPO_LIST[@]}"; do
            printf "  ${CYAN}[ %02d ]${NC} %s\n" "$((i+1))" "${REPO_LIST[$i]}"
        done
        echo -e "${CYAN}=================================================================================${NC}"
        echo ""

        read -p "Select corresponding target key identifier: " REPO_CHOICE

        # Validates that the user entered a valid number corresponding to the menu.
        if ! [[ "$REPO_CHOICE" =~ ^[0-9]+$ ]] || [ "$REPO_CHOICE" -le 0 ] || [ "$REPO_CHOICE" -gt "${#REPO_LIST[@]}" ]; then
            echo -e "${RED}[ERROR] Invalid selection index. Terminating sequence.${NC}"
            exit 1
        fi

        TARGET_REPO="${REPO_LIST[$((REPO_CHOICE-1))]}"
        TARGET_DIR="$DEV_BASE_DIR/$TARGET_REPO"

        # Prevents overwriting an existing local directory.
        if [ -d "$TARGET_DIR" ]; then
            echo -e "${RED}[ERROR] Target directory $TARGET_DIR already exists. Operation blocked.${NC}"
            exit 1
        fi

        cd "$DEV_BASE_DIR"
        echo -e "${PURPLE}[INFO] Cloning '$TARGET_REPO' into local workspace...${NC}"

        # Downloads the repository utilizing the embedded token for secure, passwordless access.
        AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
        git clone "$AUTH_REPO_URL"

        # Navigates into the newly downloaded repository and sets up the local user configuration.
        cd "$TARGET_DIR"
        git config user.name "$GITHUB_USER"
        git config user.email "$GITHUB_EMAIL"

        echo -e "${GREEN}[SUCCESS] Clone complete. Repository deployed to $TARGET_DIR.${NC}"
        ;;

    *)
        # Triggers if the user enters anything other than 1, 2, or 3 on the main menu.
        echo -e "${RED}[ERROR] Invalid protocol selected. Terminating sequence.${NC}"
        exit 1
        ;;
esac