#!/bin/bash
# ==============================================================================
# STUDIO GIT ORCHESTRATOR — PUBLIC TEMPLATE
# ==============================================================================
# This utility provides an automated, stable bridge between local/cloud AI
# environments and GitHub. It manages Python virtual environment scaffolding,
# Gemini-assisted commit generation, dynamic repository provisioning, and
# explicit multi-account identity routing with auto-detection fallback.
#
# ------------------------------------------------------------------------------
# TEMPLATE NOTICE:
# ------------------------------------------------------------------------------
# This is a REDACTED TEMPLATE intended for public distribution. All sensitive
# credentials have been replaced with placeholder values. Before execution:
#
#   1. Copy this file to 'orchestrator.sh' (the operational filename).
#   2. Add 'orchestrator.sh' to your .gitignore IMMEDIATELY.
#   3. Replace all placeholder values in the CONFIGURATION MATRIX below.
#   4. Replace INSERT_HOME_HOSTNAME_HERE with the output of: hostname
#   5. Make executable: chmod +x orchestrator.sh
#   6. Run from a project directory: ./orchestrator.sh
#
# ------------------------------------------------------------------------------
# CREDENTIAL ACQUISITION:
# ------------------------------------------------------------------------------
#   - GitHub Personal Access Tokens (classic, 'repo' scope required):
#     https://github.com/settings/tokens
#
#   - Google Gemini API Key (free tier available):
#     https://aistudio.google.com/app/apikey
#
# ------------------------------------------------------------------------------
# SECURITY NOTICE:
# ------------------------------------------------------------------------------
# NEVER commit 'orchestrator.sh' to any repository. The operational file
# contains plaintext Personal Access Tokens. Treat it as you would treat
# a private SSH key or password vault export.
# ==============================================================================

# ------------------------------------------------------------------------------
# ENFORCE STRICT ERROR HANDLING
# ------------------------------------------------------------------------------
# Halts script execution immediately upon any command failure to prevent
# cascading errors across downstream operations.
set -e

# ==============================================================================
# 1. CONFIGURATION MATRIX & CREDENTIALS
# ==============================================================================
# Hostname-based auto-detection seeds the default identity matrix.
# The Universal Identity Gate may override these values at runtime.
#
# REPLACE ALL PLACEHOLDER VALUES BELOW BEFORE FIRST EXECUTION.

if [[ "$HOSTNAME" == "INSERT_HOME_HOSTNAME_HERE" ]]; then
    # --- WORK ENVIRONMENT (DEFAULT FALLBACK) ---
    DEFAULT_GITHUB_USER="your-work-github-username"
    DEFAULT_GITHUB_EMAIL="your.work@email.com"
    DEFAULT_GITHUB_TOKEN="ghp_REPLACE_WITH_YOUR_WORK_GITHUB_PAT"
    ALT_GITHUB_USER="your-personal-github-username"
    ALT_GITHUB_EMAIL="your.personal@email.com"
    ALT_GITHUB_TOKEN="ghp_REPLACE_WITH_YOUR_PERSONAL_GITHUB_PAT"
else
    # --- HOME ENVIRONMENT ---
    DEFAULT_GITHUB_USER="your-personal-github-username"
    DEFAULT_GITHUB_EMAIL="your.personal@email.com"
    DEFAULT_GITHUB_TOKEN="ghp_REPLACE_WITH_YOUR_PERSONAL_GITHUB_PAT"
    ALT_GITHUB_USER="your-work-github-username"
    ALT_GITHUB_EMAIL="your.work@email.com"
    ALT_GITHUB_TOKEN="ghp_REPLACE_WITH_YOUR_WORK_GITHUB_PAT"
fi

GEMINI_API_KEY="REPLACE_WITH_YOUR_GEMINI_API_KEY"
DEV_BASE_DIR="$HOME/Development"

# Runtime identity variables (populated by load_identity_matrix).
GITHUB_USER=""
GITHUB_EMAIL=""
GITHUB_TOKEN=""

# ------------------------------------------------------------------------------
# TERMINAL AESTHETICS (ANSI Escape Codes)
# ------------------------------------------------------------------------------
# Color palette aligned with Manjaro Linux terminal aesthetic.
# Documentation: https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
LIME='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ==============================================================================
# TERMINAL MASKING & SAFETY PROTOCOLS
# ==============================================================================
if [ -t 0 ]; then
    stty -ctlecho 2>/dev/null || true
fi

function reset_terminal_matrix() {
    if [ -t 0 ]; then
        stty ctlecho 2>/dev/null || true
    fi
}
trap reset_terminal_matrix EXIT

function handle_keyboard_interrupt() {
    echo -e "\n\n${RED}[ERROR] Operational Exception: Termination signal intercepted.${NC}"
    echo -e "${LIME}[INFO] Decoupling workflows and cleaning up the terminal...${NC}"
    cleanup_merge_state
    echo ""
    exit 130
}

# Extended signal trap covers keyboard interrupts, kill signals, and terminal hangups.
# Documentation: https://www.gnu.org/software/bash/manual/html_node/Signals.html
trap handle_keyboard_interrupt SIGINT SIGTERM SIGHUP

# ==============================================================================
# MID-MERGE STATE RECOVERY
# ==============================================================================
# Detects partial-merge artifacts left behind by interrupted git operations
# and restores the working tree to a clean, recoverable state.
function cleanup_merge_state() {
    if [ -d ".git" ]; then
        if [ -f ".git/MERGE_HEAD" ]; then
            echo -e "${YELLOW}[WARNING] Detected interrupted merge state. Executing abort...${NC}"
            git merge --abort 2>/dev/null || true
        fi
        if [ -f ".git/index.lock" ]; then
            echo -e "${YELLOW}[WARNING] Detected stale index lock. Releasing...${NC}"
            rm -f ".git/index.lock"
        fi
    fi
}

# ==============================================================================
# PRE-FLIGHT DEPENDENCY VERIFICATION
# ==============================================================================
function verify_system_dependencies() {
    local missing_deps=()
    for binary in curl jq git python3; do
        if ! command -v "$binary" &> /dev/null; then
            missing_deps+=("$binary")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}[ERROR] Structural failure: Missing required system binaries: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}[WARNING] Please run: sudo apt update && sudo apt install -y ${missing_deps[*]} (or equivalent)${NC}"
        exit 1
    fi
}

verify_system_dependencies

# ==============================================================================
# 2. IDENTITY BANNER RENDERER
# ==============================================================================
# Renders the locked identity matrix card using Unicode-safe column padding.
# Uses wc -m to count visible glyphs rather than bytes, ensuring proper
# alignment when content contains multi-byte characters (em dashes, etc.).
function display_identity_banner() {
    local title="$1"
    local user="$2"
    local email="$3"
    local hostname_line="$4"

    # Inner content width (between gutters): 58 visible columns.
    local inner_width=58

    # Pads a string to the specified visible width using space characters.
    # Counts visible glyphs (wc -m) instead of bytes to handle Unicode safely.
    pad_to_width() {
        local text="$1"
        local target="$2"
        local current
        current=$(printf '%s' "$text" | wc -m)
        local pad_count=$((target - current))
        if [ "$pad_count" -lt 0 ]; then pad_count=0; fi
        printf '%s%*s' "$text" "$pad_count" ""
    }

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $(pad_to_width "$title" $inner_width)  ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    if [ -n "$hostname_line" ]; then
        echo -e "${CYAN}║  $(pad_to_width "Hostname:  $hostname_line" $inner_width)  ║${NC}"
    fi
    echo -e "${CYAN}║  $(pad_to_width "Account:   $user" $inner_width)  ║${NC}"
    echo -e "${CYAN}║  $(pad_to_width "Email:     $email" $inner_width)  ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Stages the active identity, presents auto-detected values, and offers an
# explicit pivot to the alternate account. Populates global GITHUB_USER,
# GITHUB_EMAIL, and GITHUB_TOKEN variables for downstream consumers.
function load_identity_matrix() {
    display_identity_banner \
        "IDENTITY MATRIX — AUTO-DETECTED" \
        "$DEFAULT_GITHUB_USER" \
        "$DEFAULT_GITHUB_EMAIL" \
        "$HOSTNAME"

    read -p "$(echo -e ${LIME}Proceed with this identity? [ y ] [ N ] : ${NC})" GATE_RESPONSE

    case $GATE_RESPONSE in
        y|Y)
            GITHUB_USER="$DEFAULT_GITHUB_USER"
            GITHUB_EMAIL="$DEFAULT_GITHUB_EMAIL"
            GITHUB_TOKEN="$DEFAULT_GITHUB_TOKEN"
            echo -e "${GREEN}[SUCCESS] Identity locked: $GITHUB_USER${NC}"
            ;;
        *)
            echo ""
            read -p "$(echo -e ${LIME}Switch to alternate account [ $ALT_GITHUB_USER ] ? [ y ] [ N ] : ${NC})" PIVOT_RESPONSE
            case $PIVOT_RESPONSE in
                y|Y)
                    display_identity_banner \
                        "IDENTITY MATRIX — MANUAL OVERRIDE" \
                        "$ALT_GITHUB_USER" \
                        "$ALT_GITHUB_EMAIL" \
                        ""

                    read -p "$(echo -e ${LIME}Confirm override? [ y ] [ N ] : ${NC})" CONFIRM_RESPONSE
                    case $CONFIRM_RESPONSE in
                        y|Y)
                            GITHUB_USER="$ALT_GITHUB_USER"
                            GITHUB_EMAIL="$ALT_GITHUB_EMAIL"
                            GITHUB_TOKEN="$ALT_GITHUB_TOKEN"
                            echo -e "${GREEN}[SUCCESS] Identity overridden: $GITHUB_USER${NC}"
                            ;;
                        *)
                            echo -e "${RED}[ABORT] Identity override declined. Terminating sequence.${NC}"
                            exit 0
                            ;;
                    esac
                    ;;
                *)
                    echo -e "${RED}[ABORT] No identity confirmed. Terminating sequence.${NC}"
                    exit 0
                    ;;
            esac
            ;;
    esac
}

# ==============================================================================
# 3. GITHUB API PROVISIONING ENGINE
# ==============================================================================
function ensure_github_repo_exists() {
    while true; do
        echo -e "${CYAN}[INFO] Validating remote repository status on GitHub: '$TARGET_REPO'...${NC}"

        HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
            -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$GITHUB_USER/$TARGET_REPO") || {
            echo -e "${RED}[ERROR] curl invocation failed when contacting GitHub API.${NC}"
            exit 1
        }

        if [ "$HTTP_STATUS" == "404" ]; then
            echo -e "\n${YELLOW}[WARNING] Repository '$TARGET_REPO' not found under '$GITHUB_USER'.${NC}"
            echo "Select a provisioning action:"
            echo "  [ c ] Provision '$TARGET_REPO' as a new private repository."
            echo "  [ r ] Retry with corrected repository name."
            echo "  [ a ] Abort operation."
            echo ""
            read -p "Selection [ c ] [ r ] [ a ] : " USER_CHOICE

            case $USER_CHOICE in
                c|C)
                    echo -e "${LIME}[INFO] Transmitting provisioning request to GitHub API...${NC}"
                    CREATE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
                        -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        -d "{\"name\":\"$TARGET_REPO\", \"private\":true}" \
                        "https://api.github.com/user/repos") || {
                        echo -e "${RED}[ERROR] curl invocation failed when creating repository.${NC}"
                        exit 1
                    }

                    if [ "$CREATE_STATUS" == "201" ]; then
                        echo -e "${GREEN}[SUCCESS] Remote repository '$TARGET_REPO' successfully provisioned.${NC}"
                        break
                    else
                        echo -e "${RED}[ERROR] Provisioning failed. GitHub API returned HTTP $CREATE_STATUS.${NC}"
                        exit 1
                    fi
                    ;;
                r|R)
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
            echo -e "${GREEN}[SUCCESS] Remote repository verified.${NC}"
            break
        elif [ "$HTTP_STATUS" == "401" ] || [ "$HTTP_STATUS" == "403" ]; then
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
# 4. AI COMMIT MESSAGE GENERATOR
# ==============================================================================
# Issues a Gemini API request to produce a Conventional Commit message based
# on the staged diff. Returns a fallback timestamp message on API failure.
function generate_ai_commit_message() {
    local commit_msg=""
    if [ "$GEMINI_API_KEY" != "REPLACE_WITH_YOUR_GEMINI_API_KEY" ]; then
        echo -e "${LIME}[INFO] Requesting AI-generated Conventional Commit message...${NC}" >&2
        local diff_preview
        diff_preview=$(git diff --cached | head -c 3000)

        local commit_prompt="You are an elite version control AI. Read this git diff and write a single, concise Conventional Commit message (e.g. feat: added parsing module). Return ONLY the message string. Do not include markdown, quotes, or explanations. Diff:"
        local payload
        payload=$(jq -n --arg prompt "$commit_prompt" --arg diff "$diff_preview" \
            '{ contents: [{ parts: [{ text: ($prompt + "\n\n" + $diff) }] }] }')

        local api_response
        api_response=$(curl -s -X POST \
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$GEMINI_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$payload")
        commit_msg=$(echo "$api_response" | jq -r '.candidates[0].content.parts[0].text' | tr -d '\n' | tr -d '"')
    fi

    if [ -z "$commit_msg" ] || [ "$commit_msg" == "null" ]; then
        commit_msg="chore: automated sync $(date "+%Y-%m-%d %H:%M:%S")"
    fi

    echo "$commit_msg"
}

# ==============================================================================
# 5. OPERATIONAL MENU ROUTER
# ==============================================================================
echo -e "${CYAN}=================================================================================${NC}"
echo -e "${CYAN}              STUDIO GIT ORCHESTRATOR${NC}"
echo -e "${CYAN}=================================================================================${NC}"
echo ""
echo -e "${LIME}Select an operational protocol:${NC}"
echo "  [ 1 ] Initialize New Workspace (VENV + Git + GitHub Sync)"
echo "  [ 2 ] Execute Automated Sync (AI Commits & GitHub Push)"
echo "  [ 3 ] Clone Existing Remote Repository"
echo "  [ 4 ] Adopt Existing Directory (Smart Detection + Manual Override)"
echo ""
read -p "Protocol Selection [ 1 ] [ 2 ] [ 3 ] [ 4 ] : " PROTOCOL

case $PROTOCOL in

    # ==========================================================================
    # PROTOCOL 1: WORKSPACE INITIALIZATION
    # ==========================================================================
    1|01)
        load_identity_matrix

        echo -e "\n${CYAN}[INFO] Initiating workspace scaffolding sequence.${NC}"
        read -p "Enter target workspace name: " PROJECT_NAME

        TARGET_REPO="$PROJECT_NAME"
        TARGET_DIR="$DEV_BASE_DIR/$PROJECT_NAME"
        SRC_DIR="$TARGET_DIR/src"

        if [ -d "$TARGET_DIR" ]; then
            echo -e "${RED}[ERROR] Target directory '$TARGET_DIR' already exists. Aborting.${NC}"
            exit 1
        fi

        echo -e "${LIME}[INFO] Provisioning Python Virtual Environment at $TARGET_DIR...${NC}"
        python3 -m venv "$TARGET_DIR"

        echo -e "${LIME}[INFO] Initializing source directory structure...${NC}"
        mkdir -p "$SRC_DIR"
        cd "$SRC_DIR"

        HTTP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' \
            -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$GITHUB_USER/$TARGET_REPO") || {
            echo -e "${RED}[ERROR] curl invocation failed when contacting GitHub API.${NC}"
            exit 1
        }

        if [ "$HTTP_STATUS" == "200" ]; then
            echo ""
            echo -e "${YELLOW}[WARNING] Repository '$TARGET_REPO' detected in cloud vault.${NC}"
            read -p "Initialize local workspace and clone remote data? [ y ] [ N ] : " USER_RESPONSE

            case $USER_RESPONSE in
                y|Y)
                    echo -e "${LIME}[INFO] Cloning remote repository...${NC}"
                    AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
                    git clone "$AUTH_REPO_URL" .

                    git config user.name "$GITHUB_USER"
                    git config user.email "$GITHUB_EMAIL"

                    echo -e "${LIME}[INFO] Restoring Python dependencies...${NC}"
                    source "$TARGET_DIR/bin/activate"

                    if [ -f requirements.txt ]; then
                        echo -e "${LIME}[INFO] requirements.txt detected. Executing installation...${NC}"
                        pip install --upgrade pip
                        pip install -r requirements.txt
                        echo -e "${GREEN}[SUCCESS] Dependencies restored.${NC}"
                    else
                        echo -e "${YELLOW}[WARNING] No requirements.txt found. Skipping.${NC}"
                    fi
                    ;;
                *)
                    echo -e "${LIME}[INFO] Operation aborted by user.${NC}"
                    exit 0
                    ;;
            esac

        else
            echo -e "${LIME}[INFO] Repository not found in cloud. Initializing fresh workspace...${NC}"
            git init
            git config user.name "$GITHUB_USER"
            git config user.email "$GITHUB_EMAIL"
            git config --global init.defaultBranch main

            ensure_github_repo_exists

            AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
            git remote add origin "$AUTH_REPO_URL"

            echo -e "${LIME}[INFO] Generating baseline configurations...${NC}"
            echo "# AI Studio Workspace | $TARGET_REPO" > README.md
            echo "Workspace initialized via Studio Git Orchestrator." >> README.md

            cat > .gitignore <<EOF
__pycache__/
.env
*.pyc
EOF

            source "$TARGET_DIR/bin/activate"
            git add .
            git commit -m "chore: initial workspace configuration and scaffolding"
            git branch -M main

            echo -e "${LIME}[INFO] Executing initial push to remote origin...${NC}"
            git push -u origin main
        fi

        echo ""
        echo -e "${GREEN}[SUCCESS] Workspace deployed successfully.${NC}"
        echo ""
        echo -e "${CYAN}[INFO] Activating virtual environment. Type 'exit' to terminate session.${NC}"

        exec bash --rcfile <(echo ". ~/.bashrc; source \"$TARGET_DIR/bin/activate\"")
        ;;

    # ==========================================================================
    # PROTOCOL 2: AUTOMATED SYNC (AI PIPELINE)
    # ==========================================================================
    2|02)
        load_identity_matrix

        echo -e "\n${CYAN}[INFO] Initiating automated synchronization sequence.${NC}"

        if [ ! -d ".git" ]; then
            echo -e "${RED}[ERROR] .git directory not found. Execute from project root.${NC}"
            exit 1
        fi

        echo -e "${LIME}[INFO] Injecting local tracking parameters...${NC}"
        git config user.name "$GITHUB_USER"
        git config user.email "$GITHUB_EMAIL"

        if git config --get remote.origin.url > /dev/null 2>&1; then
            REPO_URL=$(git config --get remote.origin.url)
            TARGET_REPO=$(basename -s .git "$REPO_URL")
        else
            TARGET_REPO=${PWD##*/}
        fi

        ensure_github_repo_exists

        AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
        git remote remove origin 2>/dev/null || true
        git remote add origin "$AUTH_REPO_URL"

        # ----------------------------------------------------
        # README GENERATION (CONDITIONAL)
        # ----------------------------------------------------
        if [ ! -f "README.md" ]; then
            echo -e "${YELLOW}[WARNING] README.md not found. Initiating generation sequence.${NC}"
            if [ "$GEMINI_API_KEY" != "REPLACE_WITH_YOUR_GEMINI_API_KEY" ]; then
                echo -e "${LIME}[INFO] Requesting AI-generated documentation...${NC}"
                DIR_TREE=$(ls -1)

                README_PROMPT="You are an elite DevSecOps architect. Write a short, powerful, enterprise-grade description based on these files. Return ONLY the text, no markdown formatting or quotes. Files:"
                PAYLOAD=$(jq -n --arg prompt "$README_PROMPT" --arg tree "$DIR_TREE" \
                    '{ contents: [{ parts: [{ text: ($prompt + "\n\n" + $tree) }] }] }')

                AI_DESC=$(curl -s -X POST \
                    "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$GEMINI_API_KEY" \
                    -H "Content-Type: application/json" \
                    -d "$PAYLOAD" | jq -r '.candidates[0].content.parts[0].text')

                echo "# AI Studio Workspace | $TARGET_REPO" > README.md
                echo "$AI_DESC" >> README.md
                echo -e "${GREEN}[SUCCESS] Documentation generated and saved.${NC}"
            else
                echo "# AI Studio Workspace" > README.md
                echo "An enterprise-grade software architecture." >> README.md
            fi
        fi

        # ----------------------------------------------------
        # STAGE & COMMIT
        # ----------------------------------------------------
        echo -e "${LIME}[INFO] Staging modified assets...${NC}"
        git add .

        if git diff --cached --quiet; then
            echo -e "${GREEN}[INFO] Working tree clean. No changes to commit.${NC}"
            exit 0
        fi

        COMMIT_MSG=$(generate_ai_commit_message)
        echo -e "${LIME}[INFO] Applying commit message: \"$COMMIT_MSG\"${NC}"
        git commit -m "$COMMIT_MSG"
        git branch -M main

        # ----------------------------------------------------
        # SECURE PUSH
        # ----------------------------------------------------
        echo -e "${LIME}[INFO] Pushing payload to remote origin...${NC}"
        if ! git push -u origin main > /dev/null 2>&1; then
            echo -e "${YELLOW}[WARNING] Fast-forward rejected. Executing force push...${NC}"
            git push -u origin main --force
        fi
        echo -e "${GREEN}[SUCCESS] Synchronization complete.${NC}"
        ;;

    # ==========================================================================
    # PROTOCOL 3: SECURE AUTOMATED CLONE
    # ==========================================================================
    3|03)
        load_identity_matrix

        echo -e "\n${CYAN}[INFO] Initiating remote repository clone sequence.${NC}"
        echo -e "${LIME}[INFO] Compiling repository inventory under '$GITHUB_USER'...${NC}"

        # Lists all repositories (public AND private) accessible to the authenticated user.
        # Documentation: https://docs.github.com/en/rest/repos/repos#list-repositories-for-the-authenticated-user
        mapfile -t REPO_LIST < <(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/user/repos?per_page=100&affiliation=owner" | jq -r '.[].name')

        if [ ${#REPO_LIST[@]} -eq 0 ]; then
            echo -e "${RED}[ERROR] Retrieval breakdown: Inventory empty or access denied.${NC}"
            exit 1
        fi

        echo -e "\n${CYAN}=================================================================================${NC}"
        echo -e "${CYAN}           AVAILABLE REMOTE CLOUD TARGETS${NC}"
        echo -e "${CYAN}=================================================================================${NC}"
        for i in "${!REPO_LIST[@]}"; do
            printf " ${CYAN}[ %02d ]${NC} %s\n" "$((i+1))" "${REPO_LIST[$i]}"
        done
        echo -e "${CYAN}=================================================================================${NC}"
        echo ""

        read -p "Select corresponding target key identifier: " REPO_CHOICE

        if ! [[ "$REPO_CHOICE" =~ ^[0-9]+$ ]] || [ "$REPO_CHOICE" -le 0 ] || [ "$REPO_CHOICE" -gt "${#REPO_LIST[@]}" ]; then
            echo -e "${RED}[ERROR] Invalid selection index. Terminating.${NC}"
            exit 1
        fi

        TARGET_REPO="${REPO_LIST[$((REPO_CHOICE-1))]}"
        TARGET_DIR="$DEV_BASE_DIR/$TARGET_REPO"

        if [ -d "$TARGET_DIR" ]; then
            echo -e "${RED}[ERROR] Target directory $TARGET_DIR already exists. Blocked.${NC}"
            exit 1
        fi

        cd "$DEV_BASE_DIR"
        echo -e "${LIME}[INFO] Cloning '$TARGET_REPO' into local workspace...${NC}"
        AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"

        git clone "$AUTH_REPO_URL"

        cd "$TARGET_DIR"
        git config user.name "$GITHUB_USER"
        git config user.email "$GITHUB_EMAIL"

        echo -e "${GREEN}[SUCCESS] Clone complete. Repository deployed to $TARGET_DIR.${NC}"
        ;;

    # ==========================================================================
    # PROTOCOL 4: ADOPT EXISTING DIRECTORY
    # ==========================================================================
    # Smart-detects whether the target directory is virgin (no .git) or
    # contaminated (existing .git with potentially wrong remote). Routes
    # through Destination Picker for explicit destination selection.
    # ==========================================================================
    4|04)
        load_identity_matrix

        echo -e "\n${CYAN}[INFO] Initiating Adoption Protocol.${NC}"
        read -p "Enter the exact name of the existing local directory: " PROJECT_NAME

        TARGET_DIR="$DEV_BASE_DIR/$PROJECT_NAME"
        SRC_DIR="$TARGET_DIR/src"

        if [ ! -d "$TARGET_DIR" ]; then
            echo -e "${RED}[ERROR] Target directory '$TARGET_DIR' does not exist. Aborted.${NC}"
            exit 1
        fi

        if [ ! -d "$SRC_DIR" ]; then
            echo -e "${YELLOW}[WARNING] '/src' subdirectory not found. Using root '$TARGET_DIR'.${NC}"
            SRC_DIR="$TARGET_DIR"
        fi

        cd "$SRC_DIR"

        # ------------------------------------------------------------------
        # STATE DETECTION: Existing .git or Virgin Folder
        # ------------------------------------------------------------------
        SKIP_PICKER=false
        if [ -d ".git" ]; then
            echo -e "\n${CYAN}[INFO] Existing .git repository detected. Auditing remote...${NC}"
            CURRENT_REMOTE=$(git config --get remote.origin.url 2>/dev/null || echo "[NONE]")

            echo -e "${YELLOW}[AUDIT] Current remote origin:${NC} $CURRENT_REMOTE"
            echo ""
            read -p "$(echo -e ${LIME}Keep this destination and sync? [ y ] [ N ] : ${NC})" KEEP_RESPONSE

            case $KEEP_RESPONSE in
                y|Y)
                    if [ "$CURRENT_REMOTE" == "[NONE]" ]; then
                        echo -e "${RED}[ERROR] No remote configured. Cannot keep null destination.${NC}"
                        exit 1
                    fi
                    TARGET_REPO=$(basename -s .git "$CURRENT_REMOTE")
                    SKIP_PICKER=true
                    echo -e "${GREEN}[INFO] Preserving existing remote. Target: $TARGET_REPO${NC}"
                    ;;
                *)
                    echo -e "${LIME}[INFO] Routing to Destination Picker for redirection...${NC}"
                    git remote remove origin 2>/dev/null || true
                    ;;
            esac
        else
            echo -e "\n${CYAN}[INFO] No .git detected. Initializing fresh repository...${NC}"
            git init
            git config --global init.defaultBranch main
        fi

        git config user.name "$GITHUB_USER"
        git config user.email "$GITHUB_EMAIL"

        # ------------------------------------------------------------------
        # DESTINATION PICKER MENU
        # ------------------------------------------------------------------
        if [ "$SKIP_PICKER" = false ]; then
            echo ""
            echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
            printf  "${CYAN}║  %-58s  ║${NC}\n" "DESTINATION SELECTION"
            printf  "${CYAN}║  Account:  %-48s  ║${NC}\n" "$GITHUB_USER"
            echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            echo "How should this directory be published?"
            echo ""
            echo "  [ 1 ] Create NEW repo with a custom name"
            echo "  [ 2 ] Push into an EXISTING repo (browse my repos)"
            echo "  [ a ] Abort"
            echo ""
            read -p "Selection [ 1 ] [ 2 ] [ a ] : " DEST_CHOICE

            case $DEST_CHOICE in

                # --------------------------------------------------
                # OPTION 1: Create NEW repo with custom name
                # --------------------------------------------------
                1)
                    read -p "Enter desired repository name (lowercase, hyphenated): " CUSTOM_NAME

                    # Format validation: lowercase, alphanumeric, hyphens only.
                    if ! [[ "$CUSTOM_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
                        echo -e "${RED}[ERROR] Invalid format. Use lowercase words separated by hyphens.${NC}"
                        exit 1
                    fi

                    TARGET_REPO="$CUSTOM_NAME"
                    ensure_github_repo_exists

                    AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
                    git remote add origin "$AUTH_REPO_URL"

                    # README handling: preserve existing or generate fresh.
                    if [ ! -f "README.md" ]; then
                        echo -e "${LIME}[INFO] No README detected. Requesting AI generation...${NC}"
                        DIR_TREE=$(ls -1)
                        README_PROMPT="You are an elite DevSecOps architect. Write a short, powerful, enterprise-grade description based on these files. Return ONLY the text, no markdown formatting or quotes. Files:"
                        PAYLOAD=$(jq -n --arg prompt "$README_PROMPT" --arg tree "$DIR_TREE" \
                            '{ contents: [{ parts: [{ text: ($prompt + "\n\n" + $tree) }] }] }')
                        AI_DESC=$(curl -s -X POST \
                            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$GEMINI_API_KEY" \
                            -H "Content-Type: application/json" \
                            -d "$PAYLOAD" | jq -r '.candidates[0].content.parts[0].text')
                        echo "# AI Studio Workspace | $TARGET_REPO" > README.md
                        echo "$AI_DESC" >> README.md
                        echo -e "${GREEN}[SUCCESS] README generated.${NC}"
                    else
                        echo -e "${GREEN}[INFO] Existing README.md preserved.${NC}"
                    fi
                    ;;

                # --------------------------------------------------
                # OPTION 2: Push into EXISTING repo
                # --------------------------------------------------
                2)
                    echo -e "${LIME}[INFO] Fetching repository inventory under '$GITHUB_USER'...${NC}"
                    mapfile -t REPO_INVENTORY < <(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                        "https://api.github.com/user/repos?per_page=100&affiliation=owner" | jq -r '.[].name')

                    if [ ${#REPO_INVENTORY[@]} -eq 0 ]; then
                        echo -e "${RED}[ERROR] No repositories available under this account.${NC}"
                        exit 1
                    fi

                    echo ""
                    # Panel geometry: 50 horizontal chars between corner glyphs.
                    # Inner content width = 46 chars (2-char gutter on each side).
                    echo -e "${CYAN}┌──────────────────────────────────────────────────┐${NC}"
                    printf  "${CYAN}│${NC}  %-46s  ${CYAN}│${NC}\n" "AVAILABLE REPOSITORIES"
                    echo -e "${CYAN}├──────────────────────────────────────────────────┤${NC}"
                    for i in "${!REPO_INVENTORY[@]}"; do
                        printf "${CYAN}│${NC}  [ %02d ]  %-38s  ${CYAN}│${NC}\n" "$((i+1))" "${REPO_INVENTORY[$i]}"
                    done
                    echo -e "${CYAN}└──────────────────────────────────────────────────┘${NC}"
                    echo ""

                    read -p "Select target repository: " REPO_PICK

                    if ! [[ "$REPO_PICK" =~ ^[0-9]+$ ]] || [ "$REPO_PICK" -le 0 ] || [ "$REPO_PICK" -gt "${#REPO_INVENTORY[@]}" ]; then
                        echo -e "${RED}[ERROR] Invalid selection index. Terminating.${NC}"
                        exit 1
                    fi

                    TARGET_REPO="${REPO_INVENTORY[$((REPO_PICK-1))]}"
                    echo ""
                    echo -e "${YELLOW}⚠  WARNING: Repository '$TARGET_REPO' may contain existing commits.${NC}"
                    echo -e "${YELLOW}   Merging local code with remote history can cause conflicts.${NC}"
                    echo ""
                    echo "Choose merge strategy:"
                    echo "  [ s ] Safe Merge   → git pull --rebase, then push (recommended)"
                    echo "  [ f ] Force Push   → OVERWRITES all remote history (DESTRUCTIVE)"
                    echo "  [ a ] Abort"
                    echo ""
                    read -p "Selection [ s ] [ f ] [ a ] : " MERGE_STRATEGY

                    AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
                    git remote add origin "$AUTH_REPO_URL"

                    case $MERGE_STRATEGY in
                        s|S)
                            echo -e "${LIME}[INFO] Executing safe merge with unrelated histories flag...${NC}"
                            # --allow-unrelated-histories permits merging two independent histories.
                            # Documentation: https://git-scm.com/docs/git-merge#Documentation/git-merge.txt---allow-unrelated-histories
                            if ! git pull origin main --allow-unrelated-histories --no-edit; then
                                echo -e "${YELLOW}[WARNING] Merge conflict detected. Applying Strategy A: favoring remote README.${NC}"
                                if [ -f ".git/MERGE_HEAD" ]; then
                                    # Auto-resolve README.md by accepting the remote version.
                                    # Documentation: https://git-scm.com/docs/git-checkout#Documentation/git-checkout.txt---theirs
                                    git checkout --theirs README.md 2>/dev/null || true
                                    git add README.md 2>/dev/null || true

                                    # If other conflicts persist, abort gracefully.
                                    if git diff --check | grep -q "conflict"; then
                                        echo -e "${RED}[ERROR] Additional conflicts beyond README detected. Aborting merge.${NC}"
                                        git merge --abort
                                        exit 1
                                    fi

                                    git commit -m "merge: integrate remote history with local adoption" --no-edit
                                fi
                            fi
                            ;;
                        f|F)
                            echo -e "${RED}[CAUTION] Force push selected. Remote history will be OVERWRITTEN.${NC}"
                            read -p "Type 'OVERWRITE' to confirm: " FORCE_CONFIRM
                            if [ "$FORCE_CONFIRM" != "OVERWRITE" ]; then
                                echo -e "${RED}[ABORT] Confirmation phrase mismatch. Aborting.${NC}"
                                exit 1
                            fi
                            ;;
                        a|A|*)
                            echo -e "${RED}[ABORT] Operation terminated by user.${NC}"
                            exit 0
                            ;;
                    esac
                    ;;

                # --------------------------------------------------
                # OPTION a: Abort
                # --------------------------------------------------
                a|A)
                    echo -e "${RED}[ABORT] Adoption Protocol terminated by user.${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}[ERROR] Invalid selection. Terminating.${NC}"
                    exit 1
                    ;;
            esac
        else
            # SKIP_PICKER path: re-attach existing remote with current identity token.
            AUTH_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${TARGET_REPO}.git"
            git remote remove origin 2>/dev/null || true
            git remote add origin "$AUTH_REPO_URL"
        fi

        # ------------------------------------------------------------------
        # COMMIT & PUSH SEQUENCE
        # ------------------------------------------------------------------
        echo -e "${LIME}[INFO] Staging all local assets...${NC}"
        git add .

        if git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
            echo -e "${GREEN}[INFO] Working tree clean. Nothing to commit.${NC}"
        else
            COMMIT_MSG=$(generate_ai_commit_message)
            echo -e "${LIME}[INFO] Applying commit message: \"$COMMIT_MSG\"${NC}"
            git commit -m "$COMMIT_MSG" || true
        fi

        git branch -M main

        echo -e "${LIME}[INFO] Executing push to remote origin...${NC}"
        if [ "$MERGE_STRATEGY" == "f" ] || [ "$MERGE_STRATEGY" == "F" ]; then
            git push -u origin main --force
        else
            git push -u origin main
        fi

        echo ""
        echo -e "${GREEN}[SUCCESS] Directory successfully adopted and synchronized.${NC}"
        echo -e "${GREEN}[INFO] Remote: https://github.com/${GITHUB_USER}/${TARGET_REPO}${NC}"
        ;;

    *)
        echo -e "${RED}[ERROR] Invalid protocol selected. Terminating sequence.${NC}"
        exit 1
        ;;
esac