中文
|
[English](README.en.md)

# Fcitx HarmonyOS Evolve

基于 [Fcitx5](https://github.com/fcitx/fcitx5) 的 HarmonyOS 拼音输入法，专注于在AI时代进行传统手搓输入体验把打字手感做好，
并与同系列的 Android、iOS 版本保持一致。

本项目 fork 自 [fcitx5-harmony](https://github.com/fcitx-contrib/fcitx5-harmony)。

> 状态：个人项目，在 HarmonyOS 7.0 真机上日常使用，尚未正式发布。暂无现成的 HAP，请自行构建（见下文）。

## 与 fcitx5-harmony 的不同

### 外观
- 浅色／深色主题，无边框按键、胶囊空格和圆形回车；按键圆角、间距可调
- 重新调校的键盘高度：按屏幕尺寸分档的固定高度，或屏幕高度百分比
- 工具栏常驻：中／英、撤销、重做、文本编辑、剪贴板、主题、更多

### 手感
- 精细调校的手势参数：滑动灵敏度、长按时长、空格滑动移动光标、退格连删
- 按键预览在手指上方，松手后保留 100 ms
- 按键震动（可调强度）与按键音

### 拼音与词库
- 优化词库导入（支持 libime `.dict`／`.txt` 和搜狗 `.scel`）
- 大幅度优化中英混输

### 符号与表情
- 分类符号键盘
- 表情与颜文字面板（长按逗号）

### 设置
- 地球键只切换中／英；长按空格选择输入法
- 设置 App 内置完整的 fcitx 设置：输入法、拼音、全局选项、附加组件
- 备份与恢复，Android 版的备份可以直接恢复
- 剪贴板面板与局域网剪贴板同步（同步默认关闭）

### 修复
- 真机上拼音不可用：HarmonyOS 原生库目录是 `libs/arm64`，改为用 `dladdr` 定位
- 输入法扩展与主应用沙箱不同，改用双方都能访问的 `distributedFilesDir` 交换设置和词库
- Debug 构建的原生代码以 -O2 编译，长句解码从每键约 100 ms 降到 25 ms

## 构建

需要 DevEco Studio（含 HarmonyOS SDK、`ohpm`、`hvigorw`）、Node.js 与 pnpm 10、gettext、wget。
以下以真机（`arm64-v8a`）为例，模拟器请换成 `x86_64`。

```sh
git clone --recursive https://github.com/Yumeri0913/Fcitx-Harmony-Evolve.git && cd Fcitx-Harmony-Evolve
npm i -g pnpm@10

# 下载预编译依赖，并构建定制的网页键盘（scripts/build-keyboard.sh）
./scripts/install-deps.sh arm64-v8a

# 给子模块打补丁
git apply --directory=entry/src/main/cpp/fcitx5 patches/fcitx5.patch
git apply --directory=entry/src/main/cpp/fcitx5-chinese-addons patches/chinese-addons.patch
git apply --directory=entry/src/main/cpp/libime patches/libime.patch

ohpm install --all
hvigorw assembleHap --mode module -p product=default -p buildABI=arm64-v8a -p buildMode=release
```

安装到真机需要签名：在 DevEco Studio 的“File → Project Structure → Signing Configs”中自动签名，
签名信息会写进 `build-profile.json5`，请不要提交这些改动。

## 上游

通用的修复欢迎回馈给 [fcitx5-harmony](https://github.com/fcitx-contrib/fcitx5-harmony)。
感谢 fcitx5-harmony 的作者和 [Fcitx](https://github.com/fcitx) 项目。

## 许可证

[GPL-3.0](LICENSE)。
