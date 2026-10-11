# IdentityV-login-helper
![Language](https://img.shields.io/badge/language-python-blue.svg)
![GitHub License](https://img.shields.io/github/license/KKeygen/idv-login)
![GitHub Release](https://img.shields.io/github/v/release/KKeygen/idv-login)
![Gitea Last Commit](https://img.shields.io/github/commits-since/KKeygen/idv-login/latest)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/KKeygen/idv-login/pack.yaml)


原项目仓库：[KKeygen/idv-login](https://github.com/KKeygen/idv-login)  ·  本分支仓库：[SangWuL/idv-login-for-mumu](https://github.com/SangWuL/idv-login-for-mumu)
教程：[click](https://kkeygenn.feishu.cn/wiki/J0V4wbm3Bi5LOVkEN7wcvwSEn0e)

## MuMu / Android 模拟器渠道服扫码复用（Windows 源码版）

本仓库包含针对 MuMu 等 Android 模拟器的辅助启动脚本。它们会以 `process` 代理模式运行本工具；完整脚本可尝试通过 ADB 将模拟器 HTTP 代理指向电脑。**脚本不会登录或保存你的游戏密码**，账号记录来自你自己完成的正常渠道服扫码流程。凭据会过期，届时必须重新扫码授权。

### 环境要求

- Windows 10/11，建议使用 Python 3.12（64 位）。
- 已安装并启动 MuMu 或其他带 ADB 支持的 Android 模拟器；已在模拟器中登录你自己的渠道服账号。
- Windows 主机与模拟器网络互通。首次配置代理/证书及工具所需的系统设置时，按提示允许管理员权限。
- 从本仓库源码运行；预编译版不包含下面的项目启动脚本。

### 安装与首次启动

在 PowerShell 中执行：

```powershell
git clone https://github.com/SangWuL/idv-login-for-mumu.git
cd idv-login-for-mumu
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

然后：

1. 启动 MuMu，并确认 ADB 已连接且在设备上允许调试授权。完整脚本会自动寻找 ADB、检测电脑局域网 IPv4 地址；有多个设备/地址时会提示选择。
2. 双击 `start-idv-login.cmd`，或在 PowerShell 执行 `powershell -ExecutionPolicy Bypass -File .\start-idv-login.ps1 -OpenUI`。在 UAC 提示中允许启动。
3. 若脚本无法自动找到 ADB，可用 `-AdbPath` 指定 `adb.exe`；有多个模拟器时用 `-DeviceSerial` 指定目标序列号。电脑有多个网卡时用 `-ProxyHost` 指定模拟器能访问的电脑 IPv4 地址：

   ```powershell
   .\start-idv-login.ps1 -OpenUI `
     -ProxyHost 192.168.1.20 `
     -AdbPath 'C:\Android\platform-tools\adb.exe' `
     -DeviceSerial '127.0.0.1:5555'
   ```

   上例地址仅为格式示例，请替换为你自己的地址和设备序列号。只运行辅助工具、不让脚本改模拟器代理时，使用 `start-idv-login-only.cmd`；该模式下需要你自行确保模拟器已指向正确的代理。
4. 首次运行时，工具会生成并导入本机代理 CA 证书。要让模拟器中的 HTTPS 请求可被代理处理，还需要在模拟器内按其 Android 版本安装/信任对应证书。只安装证书并不能绕过游戏自身的证书固定（certificate pinning）；若游戏拒绝代理连接，请停止并按受支持的网络方式排查，不要尝试绕过安全校验。
5. 在工具管理页面开启扫码记录，然后在模拟器内进入**官方渠道服**登录界面，用你自己的渠道服账号正常扫描游戏显示的新二维码并完成登录。成功后，工具会保存可用的渠道记录并将其设为该游戏默认自动登录账号；以后会尝试对新二维码自动确认。它不复用旧二维码或一次性登录码。
6. 下次启动时保持工具运行，再打开游戏。若凭据过期、被撤销或服务端拒绝，重新手动扫码即可更新记录。不要同时让多个模拟器/PC 游戏争用同一个账号选择状态。

### 脚本选项与代理恢复

```powershell
# 只启动工具并打开管理页面，不改 Android 代理
.\start-idv-login-only.ps1 -OpenUI

# 只设置 Android 全局代理，不启动工具
.\start-idv-login.ps1 -ProxifyOnly

# 完全跳过 ADB/模拟器代理配置（需自行配置代理）
.\start-idv-login.ps1 -SkipProxy -ProxyHost 127.0.0.1
```

完整脚本默认会修改所选模拟器的 Android 全局 `http_proxy`。如需恢复模拟器的系统代理，在对应设备执行（需 ADB）：

```powershell
adb devices
adb -s '<设备序列号>' shell settings put global http_proxy :0
adb -s '<设备序列号>' shell settings get global http_proxy
```

确认代理已清除后，可从模拟器证书设置中移除不再使用的用户 CA。不要删除工具工作目录中的账号记录或证书前先备份；不要分享账号数据、日志中的敏感信息、令牌或抓包文件。

### 常见问题

- **脚本找不到 Python 环境**：按上面的步骤在仓库根目录建立 `.venv` 并安装 `requirements.txt`。
- **找不到 ADB/设备**：确认模拟器已启动并授权调试；在 PowerShell 检查 `adb devices`，必要时传入 `-AdbPath` 和 `-DeviceSerial`。
- **模拟器连不上代理**：检查 `-ProxyHost` 是否是模拟器可路由到的电脑网卡地址、代理端口（默认 `10717`）是否被占用，以及 Windows 防火墙是否允许模拟器所在网络访问该端口。不要无必要地绑定 `0.0.0.0` 或向公网开放端口。
- **扫码记录没有保存/自动确认失败**：确认工具启动期间相关请求确实经过代理，管理页面已开启扫码记录，并使用新二维码完成一次正常扫码；账号凭据可能过期，重扫后再试。
- **停止使用**：先退出工具，再按上面的命令清除模拟器 HTTP 代理。异常退出后检查 hosts/系统代理是否由工具恢复；不要直接删除系统文件作为常规操作。

更多适用范围与限制见 [MuMu 阴阳师扫码记录说明](docs/mumu-onmyoji-scan-login.md)。该流程目前按 Windows + MuMu 的目标环境编写；其他模拟器的 ADB 路径、连接方式和证书行为可能不同，欢迎反馈并补充验证结果。

## 1. 使用方式

### macOS 用户

请参阅 [macOS 使用教程](docs/macOS-tutorial.md)（仅支持 Apple Silicon）

### 使用预编译版本（Windows）
1. 从本仓库的``release``页下载最新版本的可执行文件(*.exe)
- **注:如果你使用的是`Windows7`，请下载带有`Py3.8`后缀的版本；如果你使用的是`Windows8`及以上版本，两者均可，推荐下载带有`Py3.12`后缀的版本**)
- 下载完成后，**强烈建议**校验其``sha256``是否与 ``release``中``.sha256``的值相同。
    如果``sha256``不同，那么您下载的文件是不安全的，可能存在盗号风险，请检查您的网络环境并重新在**官方仓库**下载文件。
2. 您可以使用 ``Windows Powershell`` 的 ``Get-FileHash`` 命令来获取文件的``sha256``值，例如，计算v5.0.0-beta版本的`sha256`可以使用以下命令：
    ```bash
    PS D:\> Get-FileHash idv-login-v5.0.0-beta.exe
    
    Algorithm       Hash
    ---------       ----
    SHA256          <这里会显示HASH值>
    ```
3. 将该压缩文件解压，在解压完的目录中直接右键**以管理员身份运行**下载的可执行文件，例如``idv-login-v5.0.0-beta.exe``，等观察到脚本提示``可以开启游戏``时，保持终端窗口**打开**，然后您可以打开游戏。    
   
4. 打开游戏后，点击登录框**右下角的"电脑"图标**（如下图所示），即可使用账号密码登录，以绕过注册时间限制。

![图1](assets/image1.png)

5. 当你成功登录进入游戏大厅后，你可以在本程序界面中使用``Ctrl+C``关闭本程序。

### 预编译版本的构建信息
1. 自`5.3.0`版本，本程序会在构建时内嵌构建信息便于溯源
2. 构建信息的格式为`actionId(commitSHA)`
3. 在 (https://github.com/KKeygen/idv-login/actions/runs/{actionId}) 处能看到本次构建的过程和构建结果的SHA256，参照上方校验方法校验即可确认工具未被篡改

### 手动构建（Optional）

* 在 Python 官网下载 Python [Python.org](https://www.python.org/downloads/release/python-3123/)
* 例：64 位电脑 [Windows installer (64-bit)](https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe)
* 安装Python时要**使用管理员权限**，自定义(Custom)安装，**添加到Path**、**为所有用户安装**和**pip**。
* 由于新版本的Python **不支持** Windows7，如需在Windows7上构建本程序，可能需要借助**Anaconda**之类的软件安装支持Windows7的python（如 python 3.8）进行构建，具体教程请自行百度。
* 下载[代码](https://github.com/KKeygen/idv-login/archive/refs/heads/one-key.zip)到本地，解压
* 进入解压后的目录，shift+鼠标右键，选择打开Powershell或终端
* 输入以下代码并回车
```bash
pip install -r requirements.txt
pyinstaller -F src/main.py -n idv-login-v10beta.exe -i assets/icon.ico --version-file assets/version.txt --uac-admin
```
* dist文件夹中的`idv-login-v10beta.exe`就是成品

### 渠道服登录

* 在扫码界面以对应渠道扫码一次
* 下次需要登录该区服时，点击扫码登录二维码下方的游戏图标，进入一个浏览器界面
* 在该界面内管理账号登录信息

* 特别地，小米、华为账号登录需要使用手动导入的方式，需要在渠道服管理界面按照提示操作。对于华为账号，每次登录均需要在浏览器中验证，建议在第一次登录华为账号时，使用账号密码登录，信任浏览器并记住密码。

### 如果程序意外退出导致开游戏后无法登录
* 在文件资源管理器里输入`%windir%\System32\drivers\etc`并回车，删除`hosts`文件，即可解除工具对网易登录的劫持。

### 网易第五人格PC端下载
* 大陆 [下载游戏](https://adl.netease.com/d/g/id5/c/gbpc)
* 海外 [下载游戏](https://h55na.gdl.easebar.com/identityv_setup_release_oversea_0112.exe)


## 2. 开源协议
本仓库使用 ``GNU General Public License 3`` 进行开源，请使用/分发本仓库的软件或源代码或衍生产品时请遵守该开源协议，并保留原始项目地址。**需要特别注意的是，根据``GPLv3``许可证的要求，如果你使用了本仓库的代码进行二次开发，那么您的代码也必须使用`GPLv3`协议开源。**

## 3. Bug 反馈
如果您在使用过程中遇到了 ``Bug``, 可以在本仓库提交 `issue` 或者加入QQ群进行反馈。

## 4. 参与本项目

### 贡献渠道服登录方式
以下渠道由于Token过期较快，需要本工具存储渠道服的session（而不是扫码时能接触到的Token）进行刷新。涉及模拟手机端SDK的行为。
| 渠道 | 描述 |
|------|------|
| ~~九游~~ | 已经解决 |
| ~~4399~~ | 已经解决 |

一个渠道服登录实现的类模板在[这里](src/channelHandler/miChannelHandler.py)。

如果你愿意参与本项目的开发，无论是否涉及新渠道服支持，很简单，提交一个Pull request即可。如果有意长期参与开发，请联系我。

## 5. 免责声明
- 一旦您使用本软件，便代表您同意以下所有条款。
- 截至北京时间2024年8月5日，没有**第五人格**用户因使用本程序导致封号，但本软件开发组成员**不保证**使用该软件不会导致封号，您的账号的最终解释权归网易所有，请自行甄别是否使用!**一旦您使用本软件，那么意味着您愿意自行承担使用该软件可能带来的任何风险和后果**
- 由于本软件为开源软件，非官方的二次开发版本有不可控的特性，如果您使用任何非官方版本导致任何后果的，由使用者独自承担全部责任！
- 如有将该软件用于非法目的或造成不良影响后果的，由使用者独自承担全部责任！
- 如果该软件侵犯了网易公司的相关权益，请相关人员及时与我们取得联系，我们将第一时做出处理。

### 6. 赞赏渠道
感谢你的使用！如果这个工具帮到了你，请考虑下赞赏开发者。你的赞赏是我更新工具的动力~

![mm_reward_qrcode_1724484746776.png](https://cdn.nlark.com/yuque/0/2024/png/47802215/1724484775106-ccdb4382-776f-4084-8504-8d2fa50272a9.png#averageHue=%235a5340&clientId=u701fd801-c106-4&from=paste&height=421&id=u5825f50f&originHeight=1190&originWidth=1190&originalType=binary&ratio=1.75&rotation=0&showTitle=false&size=213500&status=done&style=none&taskId=u50885951-155d-4ba0-8e53-dfc47d8a1ba&title=&width=421)



BTC:
> zpub6oDW9BSHBuMqrx5qyzTM4igVZ6ycza1HroAsrSFnnRE91tNQrKAE5m2hwbM24Z8MYWY73kQB3nCH1N9LFwbDRUPa35bpzkZsb7EktaYWMqW

BTC 闪电网络:
> 02b21f493c8aa5be24c5764638e960858727d18c616257a5154b10f47b06840411

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=KKeygen/idv-login&type=Date)](https://www.star-history.com/#KKeygen/idv-login&Date)
