#!/bin/bash
set -e
R='\033[0;31m';G='\033[0;32m';Y='\033[1;33m';B='\033[0;34m';C='\033[0;36m';N='\033[0m'
info(){ echo -e "${B}[INFO]${N} $1"; }
ok(){ echo -e "${G}[OK]${N} $1"; }
warn(){ echo -e "${Y}[WARN]${N} $1"; }
err(){ echo -e "${R}[ERROR]${N} $1"; }
step(){ echo -e "${C}[STEP]${N} $1"; }

clear
echo "========================================"
echo -e "${C}  AI 工具一键安装${N}"
echo "========================================"
echo ""

# ==================== 国内路线选择 ====================
echo -e "${C}  选择国内加速路线:${N}"
echo "  [1] 阿里云"
echo "  [2] 清华源"
echo "  [3] 中科大"
echo "  [4] 腾讯云"
echo "  [5] 官方源"
read -p "  输入[1-5]: " route

NPM_REG="https://registry.npmjs.org"
APT_URL=""
NODE_URL="https://deb.nodesource.com/setup_20.x"

case "$route" in
  1) NPM_REG="https://registry.npmmirror.com"; APT_URL="https://mirrors.aliyun.com/debian"; info "路线: 阿里云" ;;
  2) NPM_REG="https://registry.npmmirror.com"; APT_URL="https://mirrors.tuna.tsinghua.edu.cn/debian"; info "路线: 清华" ;;
  3) NPM_REG="https://registry.npmmirror.com"; APT_URL="https://mirrors.ustc.edu.cn/debian"; info "路线: 中科大" ;;
  4) NPM_REG="https://mirrors.cloud.tencent.com/npm"; APT_URL="https://mirrors.cloud.tencent.com/debian"; info "路线: 腾讯云" ;;
  *) info "路线: 官方源" ;;
esac

[ -z "$TERMUX_VERSION" ] && [ ! -d "/data/data/com.termux" ] && { err "请在 Termux 运行"; exit 1; }

# ==================== Termux 部分 ====================
echo ""; step "[1/3] 更新 Termux..."
pkg update -y
ok "Termux 已更新"

echo ""; step "[2/3] 安装 proot-distro..."
command -v proot-distro &>/dev/null || pkg install proot-distro -y
ok "proot-distro 就绪"

echo ""; step "[3/3] 安装 Debian..."
DEBIAN_ROOT="/data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/debian"
if [ -d "$DEBIAN_ROOT" ]; then
  warn "Debian 已存在"
  read -p "重装? [y/N] " r
  [ "$r" = "y" ] && { proot-distro reset debian 2>/dev/null || proot-distro remove debian; proot-distro install debian; }
else
  proot-distro install debian
fi
ok "Debian 就绪"

# ==================== 写入容器脚本 ====================
step "准备容器脚本..."
mkdir -p "$DEBIAN_ROOT/tmp"

cat > "$DEBIAN_ROOT/tmp/install.sh" << INSIDE
#!/bin/bash
set -e
R='\033[0;31m';G='\033[0;32m';Y='\033[1;33m';B='\033[0;34m';C='\033[0;36m';N='\033[0m'
info(){ echo -e "\${B}[INFO]\${N} \$1"; }
ok(){ echo -e "\${G}[OK]\${N} \$1"; }
step(){ echo -e "\${C}[STEP]\${N} \$1"; }

step "配置软件源..."
if [ -n "$APT_URL" ]; then
  cat > /etc/apt/sources.list << APTEOF
deb $APT_URL trixie main contrib non-free non-free-firmware
deb $APT_URL trixie-updates main contrib non-free non-free-firmware
APTEOF
fi
apt update && apt install -y curl git ca-certificates locales
locale-gen en_US.UTF-8 zh_CN.UTF-8 2>/dev/null || true
echo 'export LANG=en_US.UTF-8' >> ~/.bashrc

step "安装 Node.js..."
if ! command -v node &>/dev/null; then
  curl -fsSL $NODE_URL | bash -
  apt install -y nodejs
fi
ok "Node: \$(node --version), npm: \$(npm --version)"
npm config set registry $NPM_REG
ok "npm: $NPM_REG"

clear
echo "========================================"
echo -e "\${C}     AI 工具安装向导\${N}"
echo "========================================"
echo ""
echo "  选择工具（可多选）:"
echo "  [1] Claude Code (官方)"
echo "  [2] Codex CLI (OpenAI)"
echo "  [3] Claude + DeepSeek"
echo "  [4] 全部安装"
read -p "  输入: " choices

C=false; X=false; D=false
case "\$choices" in *1*) C=true ;; esac
case "\$choices" in *2*) X=true ;; esac
case "\$choices" in *3*) D=true ;; esac
case "\$choices" in *4*) C=true;X=true;D=true ;; esac
[ "\$C" = false ] && [ "\$X" = false ] && [ "\$D" = false ] && { err "未选择"; exit 1; }

if [ "\$C" = true ] || [ "\$D" = true ]; then
  echo ""; step "安装 Claude..."
  npm install -g @anthropic-ai/claude-code
  CD="\$(npm root -g)/@anthropic-ai/claude-code"
  V=\$(curl -sL "https://downloads.claude.ai/claude-code-releases/stable")
  info "版本: \$V"
  mkdir -p "\$CD/bin"
  curl -L -o "\$CD/bin/claude" "https://downloads.claude.ai/claude-code-releases/\${V}/linux-arm64/claude"
  chmod +x "\$CD/bin/claude"
  ln -sf "\$CD/bin/claude" /usr/local/bin/claude-bin
  echo '{"hasCompletedOnboarding":true}' > ~/.claude.json
  ok "Claude: \$(claude-bin --version)"
fi

if [ "\$X" = true ]; then
  echo ""; step "安装 Codex..."
  npm install -g @openai/codex
  XD="\$(npm root -g)/@openai/codex"
  T=\$(curl -sL "https://api.github.com/repos/openai/codex/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
  info "版本: \$T"
  mkdir -p "\$XD/bin"
  curl -L -o /tmp/codex.tar.gz "https://github.com/openai/codex/releases/download/\${T}/codex-aarch64-unknown-linux-musl.tar.gz"
  tar -xzf /tmp/codex.tar.gz -C "\$XD/bin" --strip-components=1
  chmod +x "\$XD/bin/codex"; rm -f /tmp/codex.tar.gz
  ln -sf "\$XD/bin/codex" /usr/local/bin/codex-fast
  ok "Codex 完成"
fi

echo ""; step "配置 API Key..."
cp ~/.bashrc ~/.bashrc.bak.\$(date +%s) 2>/dev/null || true
sed -i '/# === AI CFG ===/,/# === END ===/d' ~/.bashrc 2>/dev/null || true
CFG="\n# === AI CFG ===\n"

if [ "\$C" = true ]; then
  echo ""; info "Claude 官方"
  echo "  https://console.anthropic.com/settings/keys"
  read -s -p "  Key (回车跳过): " k; echo ""
  [ -n "\$k" ] && CFG+="export ANTHROPIC_API_KEY=\"\$k\"\n"
fi

if [ "\$D" = true ]; then
  echo ""; info "DeepSeek 配置"
  echo "  https://platform.deepseek.com/api_keys"
  read -s -p "  Key (回车跳过): " k; echo ""
  echo "  选择模型:"
  echo "    [1] deepseek-chat     (通用对话)"
  echo "    [2] deepseek-reasoner (推理)"
  echo "    [3] deepseek-coder    (代码)"
  read -p "  [1-3,默认1]: " m
  case "\$m" in 2) M="deepseek-reasoner" ;; 3) M="deepseek-coder" ;; *) M="deepseek-chat" ;; esac
  if [ -n "\$k" ]; then
    CFG+="export ANTHROPIC_BASE_URL=\"https://api.deepseek.com/anthropic\"\n"
    CFG+="export ANTHROPIC_AUTH_TOKEN=\"\$k\"\n"
    CFG+="export ANTHROPIC_MODEL=\"\$M\"\n"
    CFG+="export ANTHROPIC_DEFAULT_OPUS_MODEL=\"\$M\"\n"
    CFG+="export ANTHROPIC_DEFAULT_SONNET_MODEL=\"\$M\"\n"
    CFG+="export ANTHROPIC_DEFAULT_HAIKU_MODEL=\"\$M\"\n"
    CFG+="export CLAUDE_CODE_SUBAGENT_MODEL=\"\$M\"\n"
    CFG+="export CLAUDE_CODE_EFFORT_LEVEL=\"max\"\n"
    ok "DeepSeek (\$M)"
  fi
fi

if [ "\$X" = true ]; then
  echo ""; info "Codex 配置"
  echo "  [1] ChatGPT登录  [2] API Key  [3]跳过"
  read -p "  [1-3]: " c
  case "\$c" in
    1) CFG+="# Codex: codex-fast login\n" ;;
    2) read -s -p "  Key: " k; echo ""
       [ -n "\$k" ] && CFG+="export OPENAI_API_KEY=\"\$k\"\n" ;;
  esac
fi

CFG+="# === END ===\n"
echo -e "\$CFG" >> ~/.bashrc
source ~/.bashrc

echo ""; step "创建启动器..."
cat > /usr/local/bin/ai-start << 'START'
#!/bin/bash
G='\033[0;32m';C='\033[0;36m';N='\033[0m'
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
read -p "  选择: " ch
i=1
[ "$HC" = true ] && [ "$HK" = true ] && { [ "$ch" = "$i" ] && { unset A B;claude-bin;exit; };((i++)); }
[ "$HD" = true ] && { [ "$ch" = "$i" ] && { claude-bin;exit; };((i++)); }
[ "$HX" = true ] && { [ "$ch" = "$i" ] && { codex-fast;exit; };((i++)); }
[ "$ch" = "0" ] && exit
echo "无效"
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
  D="$(npm root -g)/@anthropic-ai/claude-code"
  V=$(curl -sL "https://downloads.claude.ai/claude-code-releases/stable")
  curl -L -o "$D/bin/claude" "https://downloads.claude.ai/claude-code-releases/${V}/linux-arm64/claude"
  chmod +x "$D/bin/claude"
  echo "  $(claude-bin --version)"
fi
if command -v codex-fast &>/dev/null; then
  echo "[2/2] 更新 Codex..."
  D="$(npm root -g)/@openai/codex"
  T=$(curl -sL "https://api.github.com/repos/openai/codex/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+')
  curl -L -o /tmp/codex.tar.gz "https://github.com/openai/codex/releases/download/${T}/codex-aarch64-unknown-linux-musl.tar.gz"
  tar -xzf /tmp/codex.tar.gz -C "$D/bin" --strip-components=1
  chmod +x "$D/bin/codex";rm -f /tmp/codex.tar.gz
  echo "  完成"
fi
echo "========================================"
echo "  更新完成！"
echo "========================================"
UPD
chmod +x /usr/local/bin/ai-update

clear
echo "========================================"
echo -e "${G}     安装完成！${N}"
echo "========================================"
echo ""
echo "  命令:"
[ "$C" = true ] && echo "    claude-bin"
[ "$X" = true ] && echo "    codex-fast"
[ "$D" = true ] && echo "    claude-bin (DeepSeek)"
echo "    ai-start"
echo "    ai-update"
echo ""
echo "  重新进入:"
echo "    proot-distro login debian"
echo "    ai-start"
echo ""
INSIDE

chmod +x "$DEBIAN_ROOT/tmp/install.sh"
ok "脚本已准备"

echo ""; step "进入 Debian 安装..."
info "按提示选择工具和输入 Key"
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
