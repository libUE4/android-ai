#!/bin/bash
# ============================================================
# Termux AI 编程工具一键安装脚本 (GitHub 最终版)
# 功能：国内镜像选择 + proot-distro Debian + Claude Code + 第三方平台配置
# 修复：
#   1. npm install 崩溃 → 使用 --ignore-scripts + 手动下载二进制
#   2. 二进制丢失 → 直接复制到 /usr/local/bin/
#   3. 模型获取被 grep 污染 → info 输出到 stderr
#   4. Auth 冲突 → 只用 ANTHROPIC_AUTH_TOKEN，不用 API_KEY
#   5. 平台不兼容 → 支持任意 OpenAI/Anthropic 兼容平台，自动获取模型
# ============================================================

set -e

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; N='\033[0m'
info(){ echo -e "${B}[INFO]${N} $1"; }
ok(){ echo -e "${G}[OK]${N} $1"; }
warn(){ echo -e "${Y}[WARN]${N} $1"; }
err(){ echo -e "${R}[ERROR]${N} $1"; }
step(){ echo -e "${C}[STEP]${N} $1"; }

# 安全的密码输入
safe_read_key() {
    local prompt="$1"
    local varname="$2"
    local key=""
    if command -v stty &>/dev/null; then
        echo -n "$prompt"
        stty -echo 2>/dev/null
        read key
        stty echo 2>/dev/null
        echo ""
    else
        echo ""
        echo -e "${Y}[注意] 当前环境不支持隐藏输入${N}"
        echo -n "$prompt"
        read key
    fi
    eval "$varname=\"$key\""
}

clear
echo "========================================"
echo -e "${C}  AI 编程工具一键安装${N}"
echo "========================================"
echo ""

[ -z "$TERMUX_VERSION" ] && [ ! -d "/data/data/com.termux" ] && { err "请在 Termux 运行"; exit 1; }

# ==================== 国内路线选择 ====================
echo -e "${C}  选择国内加速路线:${N}"
echo "  [1] 阿里云  [2] 清华源  [3] 中科大  [4] 腾讯云  [5] 官方源"
read -p "  输入[1-5]: " route

NPM_REG="https://registry.npmjs.org"; APT_URL=""; NODE_URL="https://deb.nodesource.com/setup_20.x"
case "$route" in
  1) NPM_REG="https://registry.npmmirror.com"; APT_URL="https://mirrors.aliyun.com/debian"; info "路线: 阿里云" ;;
  2) NPM_REG="https://registry.npmmirror.com"; APT_URL="https://mirrors.tuna.tsinghua.edu.cn/debian"; info "路线: 清华" ;;
  3) NPM_REG="https://registry.npmmirror.com"; APT_URL="https://mirrors.ustc.edu.cn/debian"; info "路线: 中科大" ;;
  4) NPM_REG="https://mirrors.cloud.tencent.com/npm"; APT_URL="https://mirrors.cloud.tencent.com/debian"; info "路线: 腾讯云" ;;
  *) info "路线: 官方源" ;;
esac

ARCH=$(uname -m)
[ "$ARCH" != "aarch64" ] && { warn "架构: $ARCH"; read -p "继续? [Y/n] " c; [ "$c" = "n" ] && exit 1; }

# ==================== Termux ====================
echo ""; step "[1/3] 更新 Termux..."
pkg update -y
ok "Termux 已更新"

echo ""; step "[2/3] 安装 proot-distro..."
command -v proot-distro &>/dev/null || pkg install proot-distro -y
ok "proot-distro 就绪"

echo ""; step "[3/3] 安装/检查 Debian..."
DEBIAN_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian"
if [ -d "$DEBIAN_ROOT" ]; then
  warn "Debian 已存在，跳过安装"
else
  proot-distro install debian
  ok "Debian 安装完成"
fi
ok "Debian 就绪"

# ==================== 写入容器脚本 ====================
step "准备容器脚本..."
mkdir -p "$DEBIAN_ROOT/tmp"

cat > "$DEBIAN_ROOT/tmp/install.sh" << 'INSIDE'
#!/bin/bash
set -e
R='\033[0;31m';G='\033[0;32m';Y='\033[1;33m';B='\033[0;34m';C='\033[0;36m';N='\033[0m'
info(){ echo -e "${B}[INFO]${N} $1"; }
ok(){ echo -e "${G}[OK]${N} $1"; }
warn(){ echo -e "${Y}[WARN]${N} $1"; }
step(){ echo -e "${C}[STEP]${N} $1"; }

safe_read_key() {
    local prompt="$1"
    local varname="$2"
    local key=""
    if command -v stty &>/dev/null; then
        echo -n "$prompt"
        stty -echo 2>/dev/null
        read key
        stty echo 2>/dev/null
        echo ""
    else
        echo ""
        echo -e "${Y}[注意] 不支持隐藏输入${N}"
        echo -n "$prompt"
        read key
    fi
    eval "$varname=\"$key\""
}

# 获取第三方平台可用模型
fetch_models() {
    local base_url="$1"
    local api_key="$2"
    local models=""
    if [ -n "$api_key" ] && command -v curl &>/dev/null; then
        info "正在获取可用模型..." >&2
        local resp
        resp=$(curl -s -m 15 "${base_url}/models" \
            -H "Authorization: Bearer $api_key" \
            -H "Content-Type: application/json" 2>/dev/null) || true
        if [ -n "$resp" ]; then
            models=$(echo "$resp" | grep -oP '"id":\s*"\K[^"]+' 2>/dev/null | sort -u | tr '\n' ' ')
        fi
    fi
    echo "$models"
}

step "配置软件源..."
if [ -n "APT_URL_PLACEHOLDER" ]; then
  cat > /etc/apt/sources.list << APTEOF
deb APT_URL_PLACEHOLDER trixie main contrib non-free non-free-firmware
deb APT_URL_PLACEHOLDER trixie-updates main contrib non-free non-free-firmware
APTEOF
fi
apt update && apt install -y curl git ca-certificates locales
locale-gen en_US.UTF-8 zh_CN.UTF-8 2>/dev/null || true
echo 'export LANG=en_US.UTF-8' >> ~/.bashrc

step "安装 Node.js..."
if ! command -v node &>/dev/null; then
  curl -fsSL NODE_URL_PLACEHOLDER | bash -
  apt install -y nodejs
fi
ok "Node: $(node --version), npm: $(npm --version)"
npm config set registry NPM_REG_PLACEHOLDER
ok "npm: NPM_REG_PLACEHOLDER"

clear
echo "========================================"
echo -e "${C}     AI 工具安装向导${N}"
echo "========================================"
echo ""
echo "  选择工具（可多选）:"
echo "  [1] Claude Code (官方)  -- 只安装，不配置 Key"
echo "  [2] Codex CLI (OpenAI)  -- 只安装，不配置 Key"
echo "  [3] Claude + 第三方平台  -- 安装 + 配置平台 Key"
echo "  [4] 全部安装"
read -p "  输入: " choices

C=false; X=false; D=false
case "$choices" in *1*) C=true ;; esac
case "$choices" in *2*) X=true ;; esac
case "$choices" in *3*) D=true ;; esac
case "$choices" in *4*) C=true;X=true;D=true ;; esac
[ "$C" = false ] && [ "$X" = false ] && [ "$D" = false ] && { err "未选择"; exit 1; }

# ==================== 安装 Claude Code ====================
if [ "$C" = true ] || [ "$D" = true ]; then
  echo ""; step "安装 Claude Code..."

  # 只装 npm 包（不触发 postinstall，避免崩溃）
  npm install -g @anthropic-ai/claude-code --ignore-scripts

  # 手动下载二进制（绕过平台检测 + 避免 npm postinstall 崩溃）
  V=$(curl -sL --max-time 10 "https://downloads.claude.ai/claude-code-releases/stable" || echo "2.1.118")
  info "版本: $V"

  mkdir -p /usr/local/bin
  curl -L --max-time 120 -o /usr/local/bin/claude-bin \
    "https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude" 2>/dev/null || \
  curl -L --max-time 120 -o /usr/local/bin/claude-bin \
    "https://ghproxy.com/https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude" 2>/dev/null || \
  curl -L --max-time 120 -o /usr/local/bin/claude-bin \
    "https://mirror.ghproxy.com/https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude" 2>/dev/null

  if [ ! -f /usr/local/bin/claude-bin ] || [ ! -s /usr/local/bin/claude-bin ]; then
    err "Claude 二进制下载失败"
    echo ""
    echo "请手动下载："
    echo "  1. 手机浏览器打开："
    echo "     https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude"
    echo "  2. 放到手机 Download 文件夹"
    echo "  3. 执行：termux-setup-storage"
    echo "  4. 执行：cp ~/storage/downloads/claude /usr/local/bin/claude-bin"
    echo "  5. 执行：chmod +x /usr/local/bin/claude-bin"
    echo ""
    exit 1
  fi

  chmod +x /usr/local/bin/claude-bin
  echo '{"hasCompletedOnboarding":true}' > ~/.claude.json
  ok "Claude Code: $(claude-bin --version)"
fi

# ==================== 安装 Codex CLI ====================
if [ "$X" = true ]; then
  echo ""; step "安装 Codex CLI..."

  # 官方 install.sh 最稳
  curl -fsSL https://github.com/openai/codex/releases/latest/download/install.sh | sh
  export PATH="/root/.local/bin:$PATH"
  ok "Codex CLI 安装完成"
fi

# ==================== 配置 API Key ====================
echo ""; step "配置 API Key..."
cp ~/.bashrc ~/.bashrc.bak.$(date +%s) 2>/dev/null || true
sed -i '/# === AI CFG ===/,/# === END ===/d' ~/.bashrc 2>/dev/null || true
CFG="\n# === AI CFG ===\n"

# Claude 官方：只安装，不配置 Key
if [ "$C" = true ]; then
  info "Claude Code (官方) 已安装，首次运行请自行登录"
fi

# 第三方平台配置
if [ "$D" = true ]; then
  echo ""; info "第三方平台配置"
  echo "  示例: https://tokenshengsheng.com"
  echo "  示例: https://api.deepseek.com"
  read -p "  请输入 API Base URL: " base_url
  [ -z "$base_url" ] && { err "URL 不能为空"; exit 1; }

  safe_read_key "  请输入 API Key: " api_key
  [ -z "$api_key" ] && { err "Key 不能为空"; exit 1; }

  # 自动获取模型
  MODELS=$(fetch_models "$base_url" "$api_key")

  if [ -z "$MODELS" ]; then
    warn "无法自动获取模型列表"
    read -p "  请手动输入模型名称: " M
    [ -z "$M" ] && M="default"
  else
    echo ""
    echo "  可用模型列表:"
    i=1
    ARR=()
    for m in $MODELS; do
      echo "    [$i] $m"
      ARR+=("$m")
      ((i++))
    done
    echo ""
    read -p "  请选择模型编号 [1-$((i-1)), 默认1]: " idx
    [ -z "$idx" ] && idx=1
    [[ "$idx" =~ ^[0-9]+$ ]] || idx=1
    [ "$idx" -lt 1 ] && idx=1
    [ "$idx" -ge "$i" ] && idx=1
    M="${ARR[$((idx-1))]}"
    ok "选择的模型: $M"
  fi

  # 写入配置（只用 AUTH_TOKEN，避免与 API_KEY 冲突）
  CFG+="export ANTHROPIC_BASE_URL=\"$base_url\"\n"
  CFG+="export ANTHROPIC_AUTH_TOKEN=\"$api_key\"\n"
  CFG+="export ANTHROPIC_MODEL=\"$M\"\n"
  CFG+="export ANTHROPIC_DEFAULT_OPUS_MODEL=\"$M\"\n"
  CFG+="export ANTHROPIC_DEFAULT_SONNET_MODEL=\"$M\"\n"
  CFG+="export ANTHROPIC_DEFAULT_HAIKU_MODEL=\"$M\"\n"
  CFG+="export CLAUDE_CODE_SUBAGENT_MODEL=\"$M\"\n"
  CFG+="export CLAUDE_CODE_EFFORT_LEVEL=\"max\"\n"
  ok "第三方平台配置完成"
fi

# Codex：只安装，不配置 Key
if [ "$X" = true ]; then
  info "Codex CLI 已安装，首次运行请执行: codex login"
fi

CFG+="# === END ===\n"
echo -e "$CFG" >> ~/.bashrc
source ~/.bashrc

# ==================== 创建启动器 ====================
echo ""; step "创建启动器..."
cat > /usr/local/bin/ai-start << 'START'
#!/bin/bash
G='\033[0;32m';C='\033[0;36m';Y='\033[1;33m';N='\033[0m'
clear
echo "========================================"
echo -e "${C}     AI 工具启动器${N}"
echo "========================================"
echo ""
HC=false;HX=false;HD=false
command -v claude-bin &>/dev/null && HC=true
command -v codex &>/dev/null && HX=true
[ -n "$ANTHROPIC_BASE_URL" ] && HD=true
[ "$HC" = true ] && echo "  v Claude Code"
[ "$HX" = true ] && echo "  v Codex CLI"
[ "$HD" = true ] && echo "  v 第三方平台"
echo ""
i=1
[ "$HC" = true ] && [ "$HD" = false ] && { echo "  [$i] Claude(官方)";((i++)); }
[ "$HD" = true ] && { echo "  [$i] Claude(第三方)";((i++)); }
[ "$HX" = true ] && { echo "  [$i] Codex CLI";((i++)); }
echo "  [0] 退出"
echo ""
read -p "  选择: " ch
i=1
[ "$HC" = true ] && [ "$HD" = false ] && { [ "$ch" = "$i" ] && { claude-bin;exit; };((i++)); }
[ "$HD" = true ] && { [ "$ch" = "$i" ] && { claude-bin;exit; };((i++)); }
[ "$HX" = true ] && { [ "$ch" = "$i" ] && { codex;exit; };((i++)); }
[ "$ch" = "0" ] && exit
echo -e "${Y}无效选择${N}"
START
chmod +x /usr/local/bin/ai-start

cat > /usr/local/bin/ai-update << 'UPD'
#!/bin/bash
set -e
echo "========================================"
echo "  AI 工具更新"
echo "========================================"
if command -v claude-bin &>/dev/null; then
  echo "[1/2] 更新 Claude..."
  V=$(curl -sL --max-time 10 "https://downloads.claude.ai/claude-code-releases/stable" || echo "2.1.118")
  curl -L --max-time 120 -o /usr/local/bin/claude-bin \
    "https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude" 2>/dev/null || \
  curl -L --max-time 120 -o /usr/local/bin/claude-bin \
    "https://ghproxy.com/https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude" 2>/dev/null
  chmod +x /usr/local/bin/claude-bin 2>/dev/null || true
  echo "  $(claude-bin --version 2>/dev/null || echo "失败")"
fi
if command -v codex &>/dev/null; then
  echo "[2/2] 更新 Codex..."
  curl -fsSL https://github.com/openai/codex/releases/latest/download/install.sh | sh
  echo "  完成"
fi
echo "========================================"
echo "  更新完成！"
echo "========================================"
UPD
chmod +x /usr/local/bin/ai-update

cat > /usr/local/bin/ai-fix << 'FIX'
#!/bin/bash
echo "========================================"
echo "  AI 工具修复"
echo "========================================"
if [ ! -f /usr/local/bin/claude-bin ] || [ ! -s /usr/local/bin/claude-bin ]; then
  echo "[修复] Claude Code..."
  V=$(curl -sL --max-time 10 "https://downloads.claude.ai/claude-code-releases/stable" || echo "2.1.118")
  curl -L --max-time 120 -o /usr/local/bin/claude-bin \
    "https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude" 2>/dev/null || \
  curl -L --max-time 120 -o /usr/local/bin/claude-bin \
    "https://ghproxy.com/https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude" 2>/dev/null
  chmod +x /usr/local/bin/claude-bin 2>/dev/null || true
  echo "  $(claude-bin --version 2>/dev/null || echo "失败")"
fi
if [ ! -f /root/.local/bin/codex ] && [ ! -f /usr/local/bin/codex ]; then
  echo "[修复] Codex CLI..."
  curl -fsSL https://github.com/openai/codex/releases/latest/download/install.sh | sh
  echo "  完成"
fi
echo "========================================"
echo "  修复完成！"
echo "========================================"
FIX
chmod +x /usr/local/bin/ai-fix

clear
echo "========================================"
echo -e "${G}     安装完成！${N}"
echo "========================================"
echo ""
echo "  可用命令:"
[ "$C" = true ] && echo "    claude-bin    - Claude Code (官方，首次运行自行登录)"
[ "$X" = true ] && echo "    codex         - Codex CLI (首次运行 codex login)"
[ "$D" = true ] && echo "    claude-bin    - Claude Code (第三方平台)"
echo "    ai-start      - 交互式启动菜单"
echo "    ai-update     - 更新所有工具"
echo "    ai-fix        - 修复丢失的工具"
echo ""
echo "  重新进入:"
echo "    proot-distro login debian"
echo "    ai-start"
echo ""
INSIDE

sed -i "s|APT_URL_PLACEHOLDER|$APT_URL|g" "$DEBIAN_ROOT/tmp/install.sh"
sed -i "s|NODE_URL_PLACEHOLDER|$NODE_URL|g" "$DEBIAN_ROOT/tmp/install.sh"
sed -i "s|NPM_REG_PLACEHOLDER|$NPM_REG|g" "$DEBIAN_ROOT/tmp/install.sh"

chmod +x "$DEBIAN_ROOT/tmp/install.sh"
ok "脚本已准备"

echo ""; step "进入 Debian 安装..."
info "按提示选择工具和输入信息"
read -p "按回车继续..."
proot-distro login debian -- bash /tmp/install.sh

echo ""
echo "========================================"
echo -e "${G}  全部完成！${N}"
echo "========================================"
echo ""
echo "  使用:"
echo "    proot-distro login debian"
echo "    ai-start"
echo ""
