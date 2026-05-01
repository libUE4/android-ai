#!/bin/bash

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

# 获取 DeepSeek 可用模型，失败返回空
fetch_deepseek_models() {
    local api_key="$1"
    local models=""
    if [ -n "$api_key" ] && command -v curl &>/dev/null; then
        # 输出到 stderr，避免被 resp 变量捕获
        info "正在获取 DeepSeek 可用模型..." >&2

        local resp
        resp=$(curl -s -m 10 "https://api.deepseek.com/models" \
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
echo "  [3] Claude + DeepSeek   -- 安装 + 配置 DeepSeek Key"
echo "  [4] 全部安装"
read -p "  输入: " choices

C=false; X=false; D=false
case "$choices" in *1*) C=true ;; esac
case "$choices" in *2*) X=true ;; esac
case "$choices" in *3*) D=true ;; esac
case "$choices" in *4*) C=true;X=true;D=true ;; esac
[ "$C" = false ] && [ "$X" = false ] && [ "$D" = false ] && { err "未选择"; exit 1; }

if [ "$C" = true ] || [ "$D" = true ]; then
  echo ""; step "安装 Claude Code..."
  npm install -g @anthropic-ai/claude-code

  # 直接下载二进制到 /usr/local/bin/（复制而非符号链接，永不丢失）
  V=$(curl -sL "https://downloads.claude.ai/claude-code-releases/stable")
  info "版本: $V"
  curl -L -o /usr/local/bin/claude-bin \
    "https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude"
  chmod +x /usr/local/bin/claude-bin

  echo '{"hasCompletedOnboarding":true}' > ~/.claude.json
  ok "Claude Code: $(claude-bin --version)"
fi

if [ "$X" = true ]; then
  echo ""; step "安装 Codex CLI..."
  npm install -g @openai/codex

  # 直接下载二进制到 /usr/local/bin/（复制而非符号链接）
  T=$(curl -sL "https://api.github.com/repos/openai/codex/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
  info "版本: $T"
  curl -L -o /tmp/codex.tar.gz \
    "https://github.com/openai/codex/releases/download/${T}/codex-aarch64-unknown-linux-musl.tar.gz"
  tar -xzf /tmp/codex.tar.gz -C /usr/local/bin --strip-components=1
  chmod +x /usr/local/bin/codex
  rm -f /tmp/codex.tar.gz
  ln -sf /usr/local/bin/codex /usr/local/bin/codex-fast
  ok "Codex CLI 安装完成"
fi

echo ""; step "配置 API Key..."
cp ~/.bashrc ~/.bashrc.bak.$(date +%s) 2>/dev/null || true
sed -i '/# === AI CFG ===/,/# === END ===/d' ~/.bashrc 2>/dev/null || true
CFG="\n# === AI CFG ===\n"

# Claude 官方：只安装，不配置 Key
if [ "$C" = true ]; then
  info "Claude Code (官方) 已安装，首次运行请自行登录"
fi

# DeepSeek：需要配置 Key
if [ "$D" = true ]; then
  echo ""; info "DeepSeek 配置"
  echo "  获取 Key: https://platform.deepseek.com/api_keys"
  safe_read_key "  请输入 DeepSeek Key: " deepseek_key

  if [ -n "$deepseek_key" ]; then
    MODELS=$(fetch_deepseek_models "$deepseek_key")

    if [ -z "$MODELS" ]; then
      warn "无法从 DeepSeek API 获取模型列表"
      warn "可能原因: Key 无效 / 网络问题 / API 限制"
      warn "已跳过 DeepSeek 自动配置"
      warn "安装完成后可手动编辑 ~/.bashrc 配置"
    else
      echo ""
      echo "  可用模型列表:"
      i=1
      SELECTED_MODELS=()
      for m in $MODELS; do
        echo "    [$i] $m"
        SELECTED_MODELS+=("$m")
        ((i++))
      done

      echo ""
      read -p "  请选择模型编号 [1-$((i-1)), 默认1]: " model_idx

      if [ -z "$model_idx" ] || ! [[ "$model_idx" =~ ^[0-9]+$ ]] || [ "$model_idx" -lt 1 ] || [ "$model_idx" -ge "$i" ]; then
        model_idx=1
      fi

      M="${SELECTED_MODELS[$((model_idx-1))]}"
      ok "选择的模型: $M"

      CFG+="export ANTHROPIC_BASE_URL=\"https://api.deepseek.com/anthropic\"\n"
      CFG+="export ANTHROPIC_AUTH_TOKEN=\"$deepseek_key\"\n"
      CFG+="export ANTHROPIC_MODEL=\"$M\"\n"
      CFG+="export ANTHROPIC_DEFAULT_OPUS_MODEL=\"$M\"\n"
      CFG+="export ANTHROPIC_DEFAULT_SONNET_MODEL=\"$M\"\n"
      CFG+="export ANTHROPIC_DEFAULT_HAIKU_MODEL=\"$M\"\n"
      CFG+="export CLAUDE_CODE_SUBAGENT_MODEL=\"$M\"\n"
      CFG+="export CLAUDE_CODE_EFFORT_LEVEL=\"max\"\n"
      ok "DeepSeek 配置完成"
    fi
  else
    warn "未输入 Key，跳过 DeepSeek 配置"
  fi
fi

# Codex：只安装，不配置 Key
if [ "$X" = true ]; then
  info "Codex CLI 已安装，首次运行请执行: codex-fast login"
fi

CFG+="# === END ===\n"
echo -e "$CFG" >> ~/.bashrc
source ~/.bashrc

echo ""; step "创建启动器..."
cat > /usr/local/bin/ai-start << 'START'
#!/bin/bash
G='\033[0;32m';C='\033[0;36m';Y='\033[1;33m';N='\033[0m'
clear
echo "========================================"
echo -e "${C}     AI 工具启动器${N}"
echo "========================================"
echo ""
HC=false;HX=false;HD=false;HK=false
command -v claude-bin &>/dev/null && HC=true
command -v codex-fast &>/dev/null && HX=true
[ -n "$ANTHROPIC_BASE_URL" ] && HD=true
[ -n "$ANTHROPIC_API_KEY" ] && HK=true
[ "$HC" = true ] && echo "  v Claude Code"
[ "$HX" = true ] && echo "  v Codex CLI"
[ "$HD" = true ] && echo "  v DeepSeek"
echo ""
i=1
[ "$HC" = true ] && [ "$HK" = true ] && { echo "  [$i] Claude(官方)";((i++)); }
[ "$HD" = true ] && { echo "  [$i] Claude(DeepSeek)";((i++)); }
[ "$HX" = true ] && { echo "  [$i] Codex CLI";((i++)); }
echo "  [0] 退出"
echo ""
read -p "  选择: " ch
i=1
[ "$HC" = true ] && [ "$HK" = true ] && { [ "$ch" = "$i" ] && { claude-bin;exit; };((i++)); }
[ "$HD" = true ] && { [ "$ch" = "$i" ] && { claude-bin;exit; };((i++)); }
[ "$HX" = true ] && { [ "$ch" = "$i" ] && { codex-fast;exit; };((i++)); }
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
  V=$(curl -sL "https://downloads.claude.ai/claude-code-releases/stable")
  curl -L -o /usr/local/bin/claude-bin \
    "https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude"
  chmod +x /usr/local/bin/claude-bin
  echo "  $(claude-bin --version)"
fi
if command -v codex-fast &>/dev/null; then
  echo "[2/2] 更新 Codex..."
  T=$(curl -sL "https://api.github.com/repos/openai/codex/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
  curl -L -o /tmp/codex.tar.gz \
    "https://github.com/openai/codex/releases/download/${T}/codex-aarch64-unknown-linux-musl.tar.gz"
  tar -xzf /tmp/codex.tar.gz -C /usr/local/bin --strip-components=1
  chmod +x /usr/local/bin/codex;rm -f /tmp/codex.tar.gz
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
if [ ! -f /usr/local/bin/claude-bin ]; then
  echo "[修复] Claude Code..."
  V=$(curl -sL "https://downloads.claude.ai/claude-code-releases/stable")
  curl -L -o /usr/local/bin/claude-bin \
    "https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude"
  chmod +x /usr/local/bin/claude-bin
  echo "  $(claude-bin --version)"
fi
if [ ! -f /usr/local/bin/codex ]; then
  echo "[修复] Codex CLI..."
  T=$(curl -sL "https://api.github.com/repos/openai/codex/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
  curl -L -o /tmp/codex.tar.gz \
    "https://github.com/openai/codex/releases/download/${T}/codex-aarch64-unknown-linux-musl.tar.gz"
  tar -xzf /tmp/codex.tar.gz -C /usr/local/bin --strip-components=1
  chmod +x /usr/local/bin/codex;rm -f /tmp/codex.tar.gz
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
[ "$X" = true ] && echo "    codex-fast    - Codex CLI (首次运行 codex-fast login)"
[ "$D" = true ] && echo "    claude-bin    - Claude Code (DeepSeek)"
echo "    ai-start      - 交互式启动菜单"
echo "    ai-update     - 更新所有工具"
echo "    ai-fix        - 修复丢失的工具"
echo ""
echo "  手动配置 DeepSeek:"
echo "    nano ~/.bashrc"
echo "    添加: export ANTHROPIC_AUTH_TOKEN=\"你的Key\""
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
info "按提示选择工具"
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
