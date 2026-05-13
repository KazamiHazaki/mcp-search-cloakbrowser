#!/usr/bin/env bash
#
# CloakBrowser MCP Server — Universal Installer
# Works on: macOS (Intel/Apple Silicon), Linux (x64/arm64), WSL
#
# Usage:
#   # From a fresh machine (clones repo):
#   curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/install.sh | bash
#
#   # From inside the repo (local install):
#   ./install.sh
#

set -euo pipefail

REPO_URL="https://github.com/CloakHQ/cloakbrowser"
INSTALL_DIR="${CLOAK_MCP_DIR:-$HOME/.cloakbrowser-mcp}"
PYTHON_MIN="3.11"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

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
# Check / find Python
# ---------------------------------------------------------------------------

find_python() {
	local candidates=("python3.13" "python3.12" "python3.11" "python3" "python")
	for cmd in "${candidates[@]}"; do
		if command -v "$cmd" &>/dev/null; then
			local version
			version=$($cmd -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "0.0")
			if [[ "$(printf '%s\n' "$PYTHON_MIN" "$version" | sort -V | head -n1)" == "$PYTHON_MIN" ]]; then
				PYTHON_CMD="$cmd"
				PYTHON_VERSION="$version"
				return 0
			fi
		fi
	done
	return 1
}

# ---------------------------------------------------------------------------
# Install uv (fast Python package manager)
# ---------------------------------------------------------------------------

install_uv() {
	if command -v uv &>/dev/null; then
		log_ok "uv already installed: $(uv --version)"
		return 0
	fi

	log_info "Installing uv (fast Python package manager)..."
	curl -fsSL https://astral.sh/uv/install.sh | bash

	# Source uv if installed to common locations
	for uv_path in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv"; do
		if [[ -x "$uv_path" ]]; then
			export PATH="$(dirname "$uv_path"):$PATH"
			break
		fi
	done

	if ! command -v uv &>/dev/null; then
		log_warn "uv not found in PATH after install. Falling back to pip."
		return 1
	fi

	log_ok "uv installed: $(uv --version)"
	return 0
}

# ---------------------------------------------------------------------------
# Setup repo (clone or use current directory)
# ---------------------------------------------------------------------------

setup_repo() {
	# Check if we're already inside a repo with the required files
	if [[ -f "$(pwd)/mcp_server.py" && -f "$(pwd)/requirements.txt" ]]; then
		INSTALL_DIR="$(pwd)"
		log_info "Using current directory as install path: $INSTALL_DIR"
		return 0
	fi

	# Otherwise clone from remote
	if [[ -d "$INSTALL_DIR/.git" ]]; then
		log_info "Updating existing repository..."
		(cd "$INSTALL_DIR" && git pull --ff-only)
	else
		log_info "Cloning repository to $INSTALL_DIR ..."
		rm -rf "$INSTALL_DIR"
		git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
	fi
	log_ok "Repository ready at $INSTALL_DIR"
}

# ---------------------------------------------------------------------------
# Create venv and install deps
# ---------------------------------------------------------------------------

setup_venv() {
	VENV_DIR="$INSTALL_DIR/.venv"

	log_info "Creating virtual environment with Python $PYTHON_VERSION..."

	if command -v uv &>/dev/null; then
		if [[ -d "$VENV_DIR" ]]; then
			log_warn "Existing venv found. Reusing (use --clear to replace)."
			uv pip install -r "$INSTALL_DIR/requirements.txt" --python "$VENV_DIR/bin/python"
		else
			uv venv --python "$PYTHON_CMD" "$VENV_DIR"
			uv pip install -r "$INSTALL_DIR/requirements.txt" --python "$VENV_DIR/bin/python"
		fi
	else
		if [[ -d "$VENV_DIR" ]]; then
			log_warn "Existing venv found. Reusing."
		else
			"$PYTHON_CMD" -m venv "$VENV_DIR"
		fi
		"$VENV_DIR/bin/pip" install --upgrade pip
		"$VENV_DIR/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
	fi

	log_ok "Dependencies installed in $VENV_DIR"
}

# ---------------------------------------------------------------------------
# Download CloakBrowser binary
# ---------------------------------------------------------------------------

download_binary() {
	log_info "Downloading CloakBrowser stealth Chromium binary (first run)..."
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

	cat > "$bin_dir/cloak-search" <<EOF
#!/usr/bin/env bash
source "$VENV_DIR/bin/activate"
exec python "$INSTALL_DIR/mcp_server.py" "\$@"
EOF
	chmod +x "$bin_dir/cloak-search"

	cat > "$bin_dir/cloak-search-http" <<EOF
#!/usr/bin/env bash
source "$VENV_DIR/bin/activate"
exec python "$INSTALL_DIR/mcp_server.py" --http "\$@"
EOF
	chmod +x "$bin_dir/cloak-search-http"

	cat > "$bin_dir/cloak-search-sse" <<EOF
#!/usr/bin/env bash
source "$VENV_DIR/bin/activate"
exec python "$INSTALL_DIR/mcp_server.py" --sse "\$@"
EOF
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
# Main
# ---------------------------------------------------------------------------

main() {
	echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
	echo -e "${GREEN}║  CloakBrowser MCP Server — Universal Installer               ║${NC}"
	echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
	echo ""

	detect_platform

	# Check Python
	if ! find_python; then
		log_error "Python $PYTHON_MIN+ is required but not found."
		log_info "Install Python 3.11+ via:"
		log_info "  macOS:   brew install python@3.11"
		log_info "  Ubuntu:  sudo apt install python3.11 python3.11-venv"
		log_info "  Arch:    sudo pacman -S python"
		log_info "  General: https://python.org/downloads"
		exit 1
	fi
	log_ok "Python found: $PYTHON_CMD (v$PYTHON_VERSION)"

	# Install uv (optional but recommended)
	install_uv || true

	# Setup repo
	setup_repo

	# Install deps
	setup_venv

	# Download binary
	download_binary

	# macOS fix
	fix_macos_gatekeeper

	# Wrapper scripts
	create_wrappers

	# Output
	print_mcp_config
	print_usage

	echo -e "${GREEN}All set! 🚀${NC}"
}

main "$@"
