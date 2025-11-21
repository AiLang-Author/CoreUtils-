#!/usr/bin/env bash
# install_ailang_utils.sh - Install AILANG utilities

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AILANG_DIR="$HOME/.local/bin/ailang"
BIN_DIR="$HOME/.local/bin"

echo -e "${BLUE}🔧 AILANG Utilities Installer${NC}"
echo "================================"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}❌ Don't run as root! Installing to user directory.${NC}"
    exit 1
fi

# Create directories
echo -e "${YELLOW}📁 Creating directories...${NC}"
mkdir -p "$AILANG_DIR"
mkdir -p "$BIN_DIR"

# NUKE EVERYTHING FIRST (WSL fix)
echo -e "${YELLOW}🧹 Cleaning up old installations...${NC}"

# More robust cleanup: remove any file or link in BIN_DIR that points to our AILANG_DIR
# This handles cases where a previous install might have left files instead of links.
find "$BIN_DIR" -maxdepth 1 -type l -exec bash -c '
    for link; do
        target=$(readlink "$link")
        if [ -n "$target" ] && [ "${target#*$AILANG_DIR}" != "$target" ]; then
            echo "  - Removing old symlink: $(basename "$link")"
            rm -f "$link"
        fi
    done
' bash {} +

# Also remove any leftover physical copies from old install methods
rm -f "$AILANG_DIR"/*_ailang

# Copy utilities using simple glob pattern
echo ""
echo -e "${YELLOW}📦 Installing utilities from dist/...${NC}"
echo ""

found_count=0

# Simple glob - find all *_exec files in dist/*/*_exec pattern
for exec_file in dist/*/*_exec dist/*_exec; do
    # Check if a file was found by the glob
    [[ -f "$exec_file" ]] || continue
    
    # Extract utility name from the executable filename (e.g., "grep_exec" -> "grep")
    base_name=$(basename "${exec_file}")
    util=${base_name%_exec}
    
    echo -e "${GREEN}  ✓ Installing ${util}${NC}"
    
    # Copy the executable to the central ailang directory
    cp "$exec_file" "$AILANG_DIR/${util}_ailang"
    chmod +x "$AILANG_DIR/${util}_ailang"

    # SIMPLIFIED: Directly create the final symlink. No need for intermediate *_ailang links.
    # This is more robust and avoids "File exists" errors.
    ln -sfn "$AILANG_DIR/${util}_ailang" "$BIN_DIR/$util"
    
    found_count=$((found_count + 1))
done

if [ $found_count -eq 0 ]; then
    echo -e "${RED}❌ No executables found in dist/!${NC}"
    echo ""
    echo "Looking for: dist/*/*_exec"
    echo ""
    echo "What I see:"
    ls -la dist/ 2>/dev/null | head -10 || echo "dist/ directory not found"
    exit 1
fi

echo ""
echo -e "${GREEN}✅ Installed $found_count utilities${NC}"

# Create manager script
echo ""
echo -e "${YELLOW}📝 Creating ailang-utils manager...${NC}"

cat > "$BIN_DIR/ailang-utils" << 'MANAGER_SCRIPT'
#!/usr/bin/env bash
# AILANG Utils Manager

AILANG_DIR="$HOME/.local/bin/ailang"
BIN_DIR="$HOME/.local/bin"

get_utils() {
    find "$AILANG_DIR" -type f -name '*_ailang' 2>/dev/null | xargs -n 1 basename | sed 's/_ailang$//' | sort | tr '\n' ' '
}

show_status() {
    echo "AILANG Utilities Status:"
    echo "========================"
    for util in $(get_utils); do
        if [ -L "$BIN_DIR/$util" ] && [[ "$(readlink "$BIN_DIR/$util")" == *"/ailang/"* ]]; then
            # Symlink exists and points to our ailang directory
            echo "  $util: ✅ AILANG"
        elif command -v "$util" >/dev/null 2>&1; then
            if [ -f "$AILANG_DIR/${util}_ailang" ]; then
                echo "  $util: ⚪️ Available (but a system version is active)"
            else
                echo "  $util: 🔵 System"
            fi
        else
            echo "  $util: ❌ Not found"
        fi
    done
}

list_utils() {
    echo "Installed AILANG Utilities:"
    echo "==========================="
    for f in "$AILANG_DIR"/*_ailang; do
        [ -f "$f" ] || continue
        util=$(basename "$f" _ailang)
        size=$(ls -lh "$f" | awk '{print $5}')
        status="⚪"
        [ -L "$BIN_DIR/$util" ] && [[ "$(readlink "$BIN_DIR/$util")" == *"/ailang/"* ]] && status="✅"
        echo "  $status $util ($size)"
    done
}

enable_util() {
    local util="$1"
    
    if [ "$util" = "all" ]; then
        for u in $(get_utils); do
            if [ -f "$AILANG_DIR/${u}_ailang" ]; then
                ln -sf "$AILANG_DIR/${u}_ailang" "$BIN_DIR/$u"
                echo "✅ Enabled $u"
            fi
        done
    else
        if [ -f "$AILANG_DIR/${util}_ailang" ]; then
            ln -sf "$AILANG_DIR/${util}_ailang" "$BIN_DIR/$util"
            echo "✅ Enabled $util"
        else
            echo "❌ $util not found in $AILANG_DIR"
            exit 1
        fi
    fi
}

disable_util() {
    local util="$1"
    
    if [ "$util" = "all" ]; then
        for u in $(get_utils); do
            if [ -L "$BIN_DIR/$u" ]; then
                target=$(readlink "$BIN_DIR/$u")
                if [[ "$target" == *"ailang"* ]]; then
                    rm "$BIN_DIR/$u"
                    echo "✅ Disabled $u"
                fi
            fi
        done
    else
        if [ -L "$BIN_DIR/$util" ]; then
            rm "$BIN_DIR/$util"
            echo "✅ Disabled $util"
        else
            echo "ℹ️  $util not currently enabled"
        fi
    fi
}

benchmark_util() {
    local util="$1"
    local iterations="${2:-100}"
    
    if [ ! -f "$AILANG_DIR/${util}_ailang" ]; then
        echo "❌ $util not found"
        exit 1
    fi
    
    # Find system utility properly
    local system_util=""
    for path in /usr/bin /bin; do
        if [ -f "$path/$util" ] && [ ! -L "$path/$util" ]; then
            system_util="$path/$util"
            break
        fi
    done
    
    if [ -z "$system_util" ]; then
        echo "❌ System $util not found"
        exit 1
    fi
    
    echo "🏋️  Benchmarking $util ($iterations iterations)..."
    echo ""
    
    # Create temp test file
    if [ "$util" = "head" ] || [ "$util" = "tail" ]; then
        seq 1 10000 > /tmp/ailang_bench_test.txt
    else
        echo "test data for benchmarking" > /tmp/ailang_bench_test.txt
        for i in {1..1000}; do
            echo "line $i with content" >> /tmp/ailang_bench_test.txt
        done
    fi
    
    echo -n "AILANG: "
    if [ "$util" = "grep" ]; then
        time (for i in $(seq 1 $iterations); do "$AILANG_DIR/${util}_ailang" "content" /tmp/ailang_bench_test.txt > /dev/null 2>&1; done) 2>&1 | grep real
    elif [ "$util" = "head" ] || [ "$util" = "tail" ] || [ "$util" = "wc" ] || [ "$util" = "cat" ]; then
        time (for i in $(seq 1 $iterations); do "$AILANG_DIR/${util}_ailang" /tmp/ailang_bench_test.txt > /dev/null 2>&1; done) 2>&1 | grep real
    elif [ "$util" = "seq" ]; then
        time (for i in $(seq 1 $iterations); do "$AILANG_DIR/${util}_ailang" 1 100 > /dev/null 2>&1; done) 2>&1 | grep real
    elif [ "$util" = "yes" ]; then
        time (for i in $(seq 1 $iterations); do "$AILANG_DIR/${util}_ailang" | head -100 > /dev/null 2>&1; done) 2>&1 | grep real
    else
        time (for i in $(seq 1 $iterations); do "$AILANG_DIR/${util}_ailang" "test" > /dev/null 2>&1; done) 2>&1 | grep real
    fi
    
    echo -n "System: "
    if [ "$util" = "grep" ]; then
        time (for i in $(seq 1 $iterations); do "$system_util" -F "content" /tmp/ailang_bench_test.txt > /dev/null 2>&1; done) 2>&1 | grep real
    elif [ "$util" = "seq" ]; then
        time (for i in $(seq 1 $iterations); do "$system_util" 1 100 > /dev/null 2>&1; done) 2>&1 | grep real
    elif [ "$util" = "yes" ]; then
        time (for i in $(seq 1 $iterations); do "$system_util" | head -100 > /dev/null 2>&1; done) 2>&1 | grep real
    elif [ "$util" = "head" ] || [ "$util" = "tail" ] || [ "$util" = "wc" ] || [ "$util" = "cat" ]; then
        time (for i in $(seq 1 $iterations); do "$system_util" /tmp/ailang_bench_test.txt > /dev/null 2>&1; done) 2>&1 | grep real
    else
        time (for i in $(seq 1 $iterations); do "$system_util" "test" > /dev/null 2>&1; done) 2>&1 | grep real
    fi
    
    rm -f /tmp/ailang_bench_test.txt
}

test_util() {
    local util="$1"
    if [ -z "$util" ]; then
        echo "Usage: ailang-utils test <util>"
        exit 1
    fi
    if [ -f "$AILANG_DIR/${util}_ailang" ]; then
        if [ "$util" = "grep" ]; then
            echo "hello world" | "$AILANG_DIR/${util}_ailang" "world"
        elif [ "$util" = "head" ] || [ "$util" = "tail" ]; then
            seq 1 20 | "$AILANG_DIR/${util}_ailang" -n 5
        elif [ "$util" = "seq" ]; then
            "$AILANG_DIR/${util}_ailang" 1 5
        else
            "$AILANG_DIR/${util}_ailang" "test"
        fi
    else
        echo "❌ $util not found"
        exit 1
    fi
}

case "$1" in
    status)
        show_status
        ;;    
    list)
        list_utils
        ;;
    enable)
        if [ -z "$2" ]; then
            echo "Usage: ailang-utils enable <util|all>"
            echo "Available: $(get_utils) all"
            exit 1
        fi
        enable_util "$2"
        ;;
    disable)
        if [ -z "$2" ]; then
            echo "Usage: ailang-utils disable <util|all>"
            echo "Available: $(get_utils) all"
            exit 1
        fi
        disable_util "$2"
        ;;
    benchmark)
        if [ -z "$2" ]; then
            echo "Usage: ailang-utils benchmark <util> [iterations]"
            exit 1
        fi
        benchmark_util "$2" "$3"
        ;;
    test)
        test_util "$2"
        ;;
    *)
        echo "AILANG Utils Manager"
        echo "===================="
        echo ""
        echo "Commands:"
        echo "  list                - Show all utilities"
        echo "  status              - Show which utilities are active"
        echo "  enable <util|all>   - Enable AILANG version"
        echo "  disable <util|all>  - Disable AILANG version"
        echo "  benchmark <util> [N]- Compare performance"
        echo "  test <util>         - Quick test"
        echo ""
        echo "Available utilities: $(get_utils)"
        echo ""
        echo "Examples:"
        echo "  ailang-utils list"
        echo "  ailang-utils status"
        echo "  ailang-utils enable grep"
        echo "  ailang-utils benchmark head 100"
        echo "  ailang-utils disable all"
        ;;
esac
MANAGER_SCRIPT

chmod +x "$BIN_DIR/ailang-utils"

echo -e "${GREEN}✅ Created ailang-utils manager${NC}"

# Check PATH
echo ""
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo -e "${YELLOW}⚠️  Add to your ~/.bashrc:${NC}"
    echo ""
    echo -e "    ${BLUE}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
    echo ""
    echo "Then run: source ~/.bashrc"
    echo ""
else
    echo -e "${GREEN}✅ PATH already configured${NC}"
fi

# Show summary
echo ""
echo -e "${BLUE}📊 Installation Summary:${NC}"
echo "========================"
ailang-utils list | head -n 20
echo "  ... (run 'ailang-utils list' for full list)"

echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo -e "${BLUE}Quick Start:${NC}"
echo "  ailang-utils status    # Check what's enabled"
echo "  head --version         # Test a utility"
echo "  ailang-utils benchmark grep  # Compare performance"
echo ""
echo -e "${YELLOW}Note: Utilities are auto-enabled! Use 'ailang-utils disable all' to revert.${NC}"
echo ""