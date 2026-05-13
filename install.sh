#!/usr/bin/env bash
#
# CloakBrowser MCP Server — Universal Installer
# Works on: macOS (Intel/Apple Silicon), Linux (x64/arm64), WSL
#
# KEY DESIGN: NEVER touches system Python.
# Uses `uv` standalone installer (no Python required).
# `uv python install` downloads prebuilt Python to ~/.local/share/uv/python/
# venv uses that isolated Python — system Python stays untouched.
#
# Usage:
#   # Fresh install
#   curl -fsSL https://raw.githubusercontent.com/KazamiHazaki/mcp-search-cloakbrowser/main/install.sh | bash
#
#   # Update existing installation
#   curl -fsSL https://raw.githubusercontent.com/KazamiHazaki/mcp-search-cloakbrowser/main/install.sh | bash -s -- --update
#
#   # Force recreate everything (nuke venv + binary + pull latest)
#   curl -fsSL .../install.sh | bash -s -- --force
#

set -euo pipefail

REPO_URL="https://github.com/KazamiHazaki/mcp-search-cloakbrowser"
INSTALL_DIR="${CLOAK_MCP_DIR:-$HOME/.cloakbrowser-mcp}"
PYTHON_MIN="3.11"

# Parse flags
FORCE=false
UPDATE=false
for arg in "$@"; do
	case "$arg" in
		--force)   FORCE=true ;;
		--update)  UPDATE=true ;;
		--help|-h)
			cat <<'EOF'
Usage: install.sh [OPTIONS]

Options:
  --update   Update existing installation (pull latest, update deps, recreate wrappers)
  --force    Full reinstall: delete venv + binary cache, then install fresh
  --help     Show this help

Examples:
  curl -fsSL .../install.sh | bash              # Fresh install
  curl -fsSL .../install.sh | bash -s -- --update  # Update existing
  ./install.sh --force                          # Force full reinstall
EOF
			exit 0
			;;
	esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "${GREEN}▶${NC} $*"; }

# Detect if this is a re-run on existing install
IS_UPDATE=false
if [[ -d "$INSTALL_DIR/.git" && -f "$INSTALL_DIR/mcp_server.py" ]]; then
	IS_UPDATE=true
fi

# --update flag is implied when re-running on existing install
if [[ "$IS_UPDATE" == true && "$FORCE" == false && "$UPDATE" == false ]]; then
	log_info "Existing installation detected. Running in UPDATE mode."
	log_info "Use --force for full reinstall, or --update to explicitly confirm."
	UPDATE=true
fi

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------

detect_platform() {
	local os arch
	os=$(uname -s | tr '[:upper:]' '[:lower:]')
	arch=$(uname -m)

	case "$os" in
		linux*)     OS="linux" ;;
		darwin*)    OS="macos" ;;
		mingw*|cygwin*|msys*) OS="windows" ;;
		*)          OS="unknown" ;;
	esac

	case "$arch" in
		x86_64|amd64) ARCH="x64" ;;
		arm64|aarch64) ARCH="arm64" ;;
		*)            ARCH="unknown" ;;
	esac

	log_info "Detected platform: $OS-$ARCH"
}

# ---------------------------------------------------------------------------
# Ensure uv is installed (standalone — does NOT need Python)
# ---------------------------------------------------------------------------

ensure_uv() {
	if command -v uv &>/dev/null; then
		log_ok "uv already installed: $(uv --version)"
		return 0
	fi

	log_info "Installing uv (standalone, no Python required)..."
	curl -fsSL https://astral.sh/uv/install.sh | bash

	# Source into current shell
	for uv_path in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv"; do
		if [[ -x "$uv_path" ]]; then
			export PATH="$(dirname "$uv_path"):$PATH"
			break
		fi
	done

	if ! command -v uv &>/dev/null; then
		log_error "uv installation failed. Please install manually: https://docs.astral.sh/uv/getting-started/installation/"
		exit 1
	fi

	log_ok "uv installed: $(uv --version)"
}

# ---------------------------------------------------------------------------
# Ensure Python 3.11+ via uv (downloads prebuilt binary, never touches system)
# ---------------------------------------------------------------------------

ensure_python() {
	log_info "Ensuring Python $PYTHON_MIN+ is available..."

	# Try to find system Python 3.11+ first
	local candidates=("python3.13" "python3.12" "python3.11")
	for cmd in "${candidates[@]}"; do
		if command -v "$cmd" &>/dev/null; then
			local version
			version=$($cmd -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
			if [[ "$(printf '%s\n' "$PYTHON_MIN" "$version" | sort -V | head -n1)" == "$PYTHON_MIN" ]]; then
				PYTHON_CMD="$cmd"
				PYTHON_VERSION="$version"
				log_ok "Using system Python: $PYTHON_CMD (v$PYTHON_VERSION)"
				return 0
			fi
		fi
	done

	# System too old — download fresh Python via uv (isolated, no system impact)
	log_warn "System Python is too old (< $PYTHON_MIN)."
	log_info "Downloading prebuilt Python $PYTHON_MIN via uv (isolated, no system changes)..."
	uv python install "$PYTHON_MIN"
	PYTHON_CMD="$(uv python find "$PYTHON_MIN")"
	PYTHON_VERSION="$PYTHON_MIN"
	log_ok "Isolated Python ready: $PYTHON_CMD (v$PYTHON_VERSION)"
}

# ---------------------------------------------------------------------------
# Setup repo (clone, update, or use current directory)
# ---------------------------------------------------------------------------

setup_repo() {
	# If running from inside the repo, use current directory
	if [[ -f "$(pwd)/mcp_server.py" && -f "$(pwd)/requirements.txt" ]]; then
		INSTALL_DIR="$(cd "$(pwd)" && pwd)"
		log_info "Using current directory as install path: $INSTALL_DIR"
		return 0
	fi

	# Force mode: wipe and clone fresh
	if [[ "$FORCE" == true && -d "$INSTALL_DIR" ]]; then
		log_warn "--force: removing existing install dir $INSTALL_DIR"
		rm -rf "$INSTALL_DIR"
	fi

	if [[ -d "$INSTALL_DIR/.git" ]]; then
		log_info "Pulling latest code..."
		cd "$INSTALL_DIR"

		# Ensure we have a remote that matches REPO_URL
		local current_origin
		current_origin=$(git remote get-url origin 2>/dev/null || echo "")
		if [[ "$current_origin" != "$REPO_URL" && "$current_origin" != "${REPO_URL}.git" ]]; then
			log_warn "Remote URL mismatch. Resetting origin to $REPO_URL"
			git remote remove origin 2>/dev/null || true
			git remote add origin "$REPO_URL"
		fi

		# Ensure tracking branch exists
		local current_branch
		current_branch=$(git branch --show-current 2>/dev/null || echo "main")
		if ! git rev-parse --abbrev-ref "@{upstream}" &>/dev/null; then
			log_info "Setting up tracking branch for $current_branch..."
			git branch -u "origin/$current_branch" "$current_branch" 2>/dev/null || true
		fi

		# Stash any local changes before pulling
		if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
			log_warn "Local changes detected, stashing before pull..."
			git stash push -m "install.sh auto-stash $(date +%Y%m%d_%H%M%S)"
		fi

		# Fetch and pull
		git fetch origin --depth=1 "$current_branch" || {
			log_error "git fetch failed. Check network or repo URL."
			exit 1
		}
		git pull --ff-only origin "$current_branch" || {
			log_error "git pull failed. Resolve conflicts manually in $INSTALL_DIR"
			exit 1
		}
		cd - >/dev/null
		log_ok "Repository updated to latest"
	else
		log_info "Cloning repository to $INSTALL_DIR ..."
		rm -rf "$INSTALL_DIR"
		git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
		log_ok "Repository cloned"
	fi

	# Ensure absolute path
	INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
	log_info "Install path: $INSTALL_DIR"

	# Verify required files exist
	if [[ ! -f "$INSTALL_DIR/requirements.txt" ]]; then
		log_error "requirements.txt missing after clone/update."
		log_info "Contents of $INSTALL_DIR:"
		ls -la "$INSTALL_DIR" || true
		exit 1
	fi
}

# ---------------------------------------------------------------------------
# Create venv and install deps
# ---------------------------------------------------------------------------

setup_venv() {
	VENV_DIR="$INSTALL_DIR/.venv"
	local req_file="$INSTALL_DIR/requirements.txt"

	# Safety: ensure requirements.txt exists
	if [[ ! -f "$req_file" ]]; then
		log_error "requirements.txt not found at $req_file"
		log_info "Listing $INSTALL_DIR:"
		ls -la "$INSTALL_DIR" || true
		exit 1
	fi

	if [[ "$FORCE" == true && -d "$VENV_DIR" ]]; then
		log_warn "--force: removing existing venv..."
		rm -rf "$VENV_DIR"
	fi

	if [[ -d "$VENV_DIR" ]]; then
		if [[ "$UPDATE" == true ]]; then
			log_info "Updating dependencies in existing venv..."
			uv pip install -r "$req_file" --python "$VENV_DIR/bin/python" --upgrade
			log_ok "Dependencies updated in $VENV_DIR"
		else
			log_warn "Existing venv found. Reusing."
			uv pip install -r "$req_file" --python "$VENV_DIR/bin/python"
			log_ok "Dependencies installed in $VENV_DIR"
		fi
	else
		log_info "Creating virtual environment with Python $PYTHON_VERSION..."
		uv venv --python "$PYTHON_CMD" "$VENV_DIR"
		uv pip install -r "$req_file" --python "$VENV_DIR/bin/python"
		log_ok "Dependencies installed in $VENV_DIR"
	fi
}

# ---------------------------------------------------------------------------
# Download CloakBrowser binary
# ---------------------------------------------------------------------------

download_binary() {
	if [[ "$FORCE" == true && -d "$HOME/.cloakbrowser" ]]; then
		log_warn "--force: clearing binary cache..."
		rm -rf "$HOME/.cloakbrowser"
	fi

	log_info "Ensuring CloakBrowser stealth Chromium binary..."
	"$VENV_DIR/bin/python" -m cloakbrowser install
	log_ok "Binary ready"
}

# ---------------------------------------------------------------------------
# macOS Gatekeeper fix
# ---------------------------------------------------------------------------

fix_macos_gatekeeper() {
	if [[ "$OS" == "macos" ]]; then
		log_info "Fixing macOS Gatekeeper for ad-hoc signed binary..."
		local chromium_app
		chromium_app=$(find "$HOME/.cloakbrowser" -name "Chromium.app" -type d 2>/dev/null | head -n1)
		if [[ -n "$chromium_app" ]]; then
			xattr -cr "$chromium_app" 2>/dev/null || true
			log_ok "Gatekeeper attributes cleared"
		fi
	fi
}

# ---------------------------------------------------------------------------
# Create wrapper scripts
# ---------------------------------------------------------------------------

create_wrappers() {
	local bin_dir="$INSTALL_DIR/bin"
	mkdir -p "$bin_dir"

	# Self-locating wrappers: detect project root from script location
	# so they work even if the install directory is moved.
	cat > "$bin_dir/cloak-search" <<'SCRIPT'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="${PROJECT_ROOT}/.venv"
if [[ -f "${VENV_DIR}/bin/activate" ]]; then
    source "${VENV_DIR}/bin/activate"
fi
exec python "${PROJECT_ROOT}/mcp_server.py" "$@"
SCRIPT
	chmod +x "$bin_dir/cloak-search"

	cat > "$bin_dir/cloak-search-http" <<'SCRIPT'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="${PROJECT_ROOT}/.venv"
if [[ -f "${VENV_DIR}/bin/activate" ]]; then
    source "${VENV_DIR}/bin/activate"
fi
exec python "${PROJECT_ROOT}/mcp_server.py" --http "$@"
SCRIPT
	chmod +x "$bin_dir/cloak-search-http"

	cat > "$bin_dir/cloak-search-sse" <<'SCRIPT'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="${PROJECT_ROOT}/.venv"
if [[ -f "${VENV_DIR}/bin/activate" ]]; then
    source "${VENV_DIR}/bin/activate"
fi
exec python "${PROJECT_ROOT}/mcp_server.py" --sse "$@"
SCRIPT
	chmod +x "$bin_dir/cloak-search-sse"

	log_ok "Wrapper scripts created in $bin_dir"
}

# ---------------------------------------------------------------------------
# MCP config helper
# ---------------------------------------------------------------------------

print_mcp_config() {
	local python_path="$VENV_DIR/bin/python"
	local server_path="$INSTALL_DIR/mcp_server.py"

	echo ""
	echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
	echo -e "${GREEN}  Installation Complete!${NC}"
	echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
	echo ""
	echo -e "${BLUE}Add this to your MCP client config:${NC}"
	echo ""
	cat <<EOF
{
  "mcpServers": {
    "cloak-search": {
      "command": "$python_path",
      "args": ["$server_path"]
    }
  }
}
EOF
	echo ""
	echo -e "${BLUE}Claude Desktop config location:${NC}"
	echo "  macOS:   ~/Library/Application Support/Claude/claude_desktop_config.json"
	echo "  Windows: %APPDATA%\\Claude\\claude_desktop_config.json"
	echo "  Linux:   ~/.config/Claude/claude_desktop_config.json"
	echo ""
}

print_usage() {
	echo -e "${GREEN}Quick Start Commands:${NC}"
	echo ""
	echo "  # HTTP mode (curl/browser access)"
	echo "  $INSTALL_DIR/bin/cloak-search-http"
	echo ""
	echo "  # MCP stdio mode (Claude Desktop, Cursor, etc.)"
	echo "  $INSTALL_DIR/bin/cloak-search"
	echo ""
	echo "  # MCP + HTTP SSE mode (both on port 8000)"
	echo "  $INSTALL_DIR/bin/cloak-search-sse"
	echo ""
	echo -e "${GREEN}Test it:${NC}"
	echo "  curl 'http://localhost:8000/search?query=hello+world&limit=3'"
	echo "  curl 'http://localhost:8000/scrape?url=https://python.org'"
	echo ""
	echo -e "${YELLOW}Tools available to LLM:${NC}"
	echo "  • search_google(query, limit=5)    — Search Google via stealth browser"
	echo "  • scrape_page(url, use_cache=true) — Scrape any page to markdown"
	echo "  • cache_status()                    — View cached pages"
	echo ""
}

# ---------------------------------------------------------------------------
# Print update summary
# ---------------------------------------------------------------------------

print_update_summary() {
	echo ""
	echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
	echo -e "${GREEN}  Update Complete! 🔄${NC}"
	echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
	echo ""
	echo -e "${BLUE}What was updated:${NC}"
	echo "  ✓ Latest code pulled from $REPO_URL"
	echo "  ✓ Python dependencies refreshed"
	echo "  ✓ Wrapper scripts regenerated"
	echo "  ✓ CloakBrowser binary verified"
	echo ""
	echo -e "${BLUE}Restart your servers:${NC}"
	echo "  # Kill old processes"
	echo "  lsof -ti:8000 | xargs kill -9 2>/dev/null || true"
	echo ""
	echo "  # Restart in your preferred mode"
	echo "  $INSTALL_DIR/bin/cloak-search       # MCP stdio"
	echo "  $INSTALL_DIR/bin/cloak-search-http  # HTTP API"
	echo "  $INSTALL_DIR/bin/cloak-search-sse   # HTTP + SSE"
	echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
	echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
	echo -e "${GREEN}║  CloakBrowser MCP Server — Universal Installer               ║${NC}"
	if [[ "$UPDATE" == true ]]; then
		echo -e "${GREEN}║  UPDATE MODE — Pulling latest, refreshing deps               ║${NC}"
	elif [[ "$FORCE" == true ]]; then
		echo -e "${GREEN}║  FORCE MODE — Full reinstall (nuking old venv + cache)       ║${NC}"
	fi
	echo -e "${GREEN}║  (System Python is NEVER touched)                            ║${NC}"
	echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
	echo ""

	detect_platform

	# Step 1: Install uv (standalone — needs nothing from the system)
	ensure_uv

	# Step 2: Get Python 3.11+ (system or uv-downloaded — never modifies system)
	ensure_python

	# Step 3: Setup repo (clone or pull latest)
	setup_repo

	# Step 4: Create/update venv and install deps
	setup_venv

	# Step 5: Download/update CloakBrowser binary
	download_binary

	# Step 6: macOS fix
	fix_macos_gatekeeper

	# Step 7: Wrapper scripts (always regenerate in case paths changed)
	create_wrappers

	# Output
	if [[ "$UPDATE" == true ]]; then
		print_update_summary
	else
		print_mcp_config
		print_usage
		echo -e "${GREEN}All set! 🚀${NC}"
		echo ""
	fi

	log_info "Your system Python was NOT modified."
	log_info "Python $PYTHON_VERSION is isolated in the virtual environment."
}

main "$@"
