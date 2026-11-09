# iOS 1.0.7（230）固件向导与 WP6 TMG3 候选

## 1.0.11（259）完整版构建 C15：TMG 刷写默认未启用（未打包、未签名、未发布）

C15 把 Turbo IO 的全部功能移植到 RayNeo AI 1.0.11（259）上，输入与仅下载构建是同一个固定哈希的第三方解密 IPA。机主已同意修改这个 IPA 里的 `App.framework`。主机检查全部通过之前不打包、不签名、不安装；装到手机上之前同样需要机主当时明确同意。

**两种 1.0.11 构建怎么区分：** 两者的 Runner 完全相同（UUID `22724C97-2EF9-388D-8E6A-6E051855A555`），只靠打包器写进 Info.plist 的 `TIOHostProfile` 区分：

- 值正好是 `ios1011`：完整版（C15），功能全开，TMG 刷写默认未启用。
- 没有这个键，或者是其他任何值（包括旧的 `ios1011-download`、大小写不同、多一个空格、不是字符串）：仍然是仅下载构建，只装 rayneonet 通道钩子，业务 9 只放行空的版本查询。之前打好的仅下载 IPA 不受影响。

**功能：** 语音接管、苹果端 AI（断网）、待办、常听、首页标签页、语言标记、咬合实验恢复、手表遥控和各个文件发送器，与 1.0.7 构建相同。扩展挂接或调用的每一个宿主方法，类型编码都已离线读出并与 1.0.7 对照，全部一致（`test.py` 的 `host-selectors` 组，54 项）；这只说明静态接口没变，功能是否真的可用要等机主在手机上确认。“导出官方固件”面板在完整版里放在“开发者”分组下，仍然只读。

**升级路由补丁：** 与 1.0.7 相同的两条字符串记录（换成本地回环地址，保留 Dart 缓存的哈希），位置换成 1.0.11 的偏移 `39886000` 和 `30868352`。输入 `App.framework/App` 的 SHA-256 必须是 `0688e01c2541e9e4b6bfadf16a87075b6ba4e5fca78f627d2ca1488cf81354be`，输出必须是 `592d48d0e42869f11def2dde99a3a6960d4da7b83b99df47d228311dfc3b8ba6`，不符就失败。打包器写入路由标记 `TIOExperimentalOTAQueryRouting = ios1011-tmg-loopback-flash-gated-arm-required`（1.0.7 的标记对 1.0.11 无效，反之亦然），内置 TMG9 ZIP（SHA-256 `def1afe2d5fdc7473147d34bd158fef3965685d1e1f57343c3753a556a7045cd`），不写 `UISupportedDevices`，打包时也不接受 `--product`。签名后再核对一次两条路由记录。

**TMG 刷写默认未启用：**

- 未启用时，业务 9 只放行官方固件页查询用的帧：空的系统版本（类型 1）、电量（类型 2）、空闲（类型 11），以及大小正好等于内置 ZIP 的空间查询（类型 3，`{OtaSize: 8819595}`）。这样官方 App 能对本地回环源做完整的更新检查，通信记录也能录到真实的顺序。
- 开始安装（类型 4，不论 Mode 是几，包括强制更新页自动发出的 `{Mode:4}`）、版本（类型 5）、清单（类型 6）和分片（类型 7）一律拒绝；不在白名单里的文件发送也拒绝。这一点**不依赖任何编译开关，也不看自动更新开关**：主机测试用六组开关分别编译同一个测试，拒绝结果必须完全一致（`ios1011-full-guard`）。
- 启用：Turbo IO →“TMG 刷机向导”→ 第 3 步“本机 TMG 刷写”一行，点“启用”，确认弹窗后才写入。启用记录保存在扩展自己的设置里（`io.turboio.official-private-addon`，键 `otaFlashArmRecord.ios1011`），绑定当前扩展库的 UUID。这个 UUID 由扩展库的内容算出，不代表“这一次安装”：扩展库哪怕只差一个字节，装上后就自动回到未启用；但原样重装同一个 IPA、或者重新打包出字节完全相同的扩展库，记录都还在。C15 → C13 → C15 这样来回装一次，记录也还在（C13 不读也不清除它）。所以**回滚之前先停用**。格式不对、别的宿主写的或别的构建写的记录都按未启用处理；启用记录只从扩展自己设置里的持久值读取，启动参数之类的临时值不算。
- 启用本身不授权任何东西。启用之后走的是 1.0.7 的同一套刷写门槛：自动更新先开后关、两分钟内的有效版本回读、已校验的 ZIP、一次确认授权；授权后只接受 `{Mode:2}`，强制更新页的 `{Mode:4}` 仍被拒绝。
- 停用：同一行点“停用”。授权后、开始传输前停用会撤销授权；**传输开始后不能停用**（中途切断会让眼镜停在刷写中途），传输照常完成。传输失败后（门槛停在失败状态）也不能停用，重启 App 后再停用。传输开始后，扩展不再读取启用记录，记录读取出错也不会打断传输。
- “导出官方固件”面板的防护行显示同一个状态：绿色“刷写未启用：拒绝 OTA 传输”（要等本次启动有一次官方调用经过防护之后才变绿，之前是橙色“尚未看到官方调用”），橙色“刷写已启用：由 TMG 向导决定”，红色表示这道防护没有生效。

**启用之前必须先抓包。** 1.0.11 的升级顺序（电量、空间、版本、开始安装，即 2/3/1/4）、类型 3 的格式，以及正常（非强制）升级页发出的 Mode，目前只来自静态反编译，**没有在设备上看到过**。启用之前，先装带通信记录的 C15（`--wire-log`），保持未启用；先在 TMG 刷机向导第 2 步点“开放下载 15 分钟”（未启用时也可以点，它不授权刷写），再在官方固件页面检查一次更新，等到“准备安装”；确认仍是未启用之后，点**一次**“开始安装”，再导出记录确认上面的顺序和格式，并记下被拒绝的那一帧开始安装里的 Mode。这一下只有在未启用时才安全：未启用时开始安装（类型 4）在任何编译开关下都会被拒绝，眼镜什么也收不到；已启用时绝对不要这样试。升级路由补丁把更新检查发到本地回环源，下载窗口没开时这个源不提供任何更新，官方页面就不会走到空间查询和开始安装。如果正常升级页发出的不是 `{Mode:2}`，门槛会拒绝它：不要为此放宽门槛，把记录交给开发者。

**打包（不涉及设备）：** `bash scripts/turbo-package.sh --host 1011-full [--wire-log] <label>`。只检查不签名：加 `--build-only`。`--host 1011` 仍然打仅下载构建，行为不变。

**回滚：** 先在 TMG 刷机向导里**停用** TMG 刷写（C13 不会清除启用记录，不停用的话以后再装回同一个 C15 时仍是启用状态）。然后与仅下载构建相同：把 C13 IPA 覆盖安装回去，不删除 App。C15 不刷眼镜，眼镜固件不需要回滚。如果已经用 C15 刷过眼镜，眼镜的回滚按对应 TMG 一节的说明进行。

机主设备检查清单见 [C15-CHECKLIST.md](C15-CHECKLIST.md)。

## 1.0.11（259）仅下载构建：导出官方固件（未打包、未发布）

这个构建只做一件事：让**原厂** RayNeo AI 1.0.11（259）从雷鸟真实服务器下载最新的官方眼镜固件，再把下载好的 ZIP 导出到 Mac 上核对哈希。它不刷写眼镜，也不包含 TMG 固件。

**现状：打包被阻塞。** 反编译已静态确认（问题 Q1）：1.0.11 的每一个业务 9 帧都经由 `rayneonet_sendMessage`，走 `RayneoNetPluginBridge -handleMethodCall:result:` 离开 Dart，也就是钩子挂住的那个方法，没有 FFI 或 pigeon 旁路。独立的反驳检查还没有结束，在它报告之前不运行 `turbo-package.sh`，不签名，不安装。下面的流程留给反驳检查结束之后、并且机主当时明确同意安装之后使用。

**它做什么、不做什么：**

- `App.framework/App` 与原厂 1.0.11 逐字节一致（只是重新签名）：不改升级路由，不走本地回环源，不内置 TMG ZIP，不写 `TIOExperimentalOTAQueryRouting`，不注入 `UISupportedDevices`。更新请求原样发往雷鸟服务器。
- 宿主按精确的版本、构建号和 Runner UUID（`22724C97-2EF9-388D-8E6A-6E051855A555`）识别为 `ios1011-download`。在这个宿主上扩展只安装 rayneonet 通道钩子，不装语音、常听、首页等功能钩子，也不主动向眼镜发送任何帧（没有语言标记推送、手表遥控或咬合实验恢复）。
- 安全网：钩子装好后，发往眼镜的业务 9 帧中**只放行空的版本查询**，其余一律拒绝，格式不对的调用也拒绝，OTA 会话（类型 4，不论 Mode 是几）无法开始。所以即使误点了“开始安装”，也刷不进去。但流程本身不依赖这一点。
- 这个拒绝**不依赖任何编译开关**（`TIO_OTA_FLASH_ENABLED`、`TIO_DISPLAY_FLASH`、`TIO_DISPLAY_PHONE`）：主机测试用四组开关分别编译同一个测试，拒绝结果必须完全一致；打包脚本在签名前检查附加库里确实带着这段 1.0.11 防护，缺了就直接失败。1.0.7 的行为不变。
- **原厂提词器的文件发送放行（D5，防护标记 `IOS1011-DOWNLOAD-GUARD-03`）：** 以前防护拒绝所有不是 Turbo IO 自己发出的 `rayneonet_sendFile`，原厂提词器因此在 1.0.7 刷机构建和 1.0.11 仅下载构建上都用不了。现在两个宿主共用同一个白名单检查，只放行完全符合下面条件的一种调用，其余文件发送（包括照片发送）照旧拒绝，业务 9 的规则也不变：
  - 方法正好是 `rayneonet_sendFile`，参数正好只有 `deviceId`、`filePath`、`taskId` 三项，而且都是非空字符串；参数必须是 Foundation 自己的字典和字符串（不接受子类或代理），检查时只读一次，拍下一份快照；
  - `deviceId` 最多 256 个字符，`user_` 后面最多 20 位 ASCII 数字（这两个上限是有意加的，比观察到的格式更严）；
  - `filePath` 是 App 自己容器里的 `Library/Application Support/user_<数字>/teleprompter/<UUID>` 或 `Documents/user_<数字>/teleprompter/<UUID>`，区分大小写，不能多一层目录，路径里不能有符号链接、`..`、`.` 或 `//`；
  - 文件名是标准格式的 UUID（全小写或全大写），`taskId` 与文件名完全相同；
  - 文件是普通文件（不是链接、硬链接、文件夹、管道或套接字），大小在 1 字节到 1 MiB 之间，开头不是 ZIP 的 `PK`，最后 65557 字节里也没有 ZIP 结尾记录的签名 `PK\x05\x06`（前面加了 BOM 或其他字节的 ZIP 同样拒绝）；
  - OTA 刷机阶段为 0（正在刷机时一律拒绝）。
  放行后，交给原厂插件的是用方法名和快照新建的调用，插件读到的正是检查过的内容。检查过程中出现任何异常都按拒绝处理。检查完到插件打开文件之间仍有一个时间窗：只有 App 自己能写这个目录（两个宿主都没有开启 `UIFileSharingEnabled`），眼镜端的接收逻辑是最后一道防线。
  眼镜端怎么处理这些字节，目前只来自静态反编译，**没有在设备上验证**：原厂 1.0.5.5 的业务 0x11 接收端在内存里拼装文件（最多 20 MiB，校验 MD5），只有业务 0x14 会使用它，内存上限约 1 MiB；没有找到写入存储的代码，但间接调用没有全部解析；1.0.5.12 按推断行为相同。主机测试 `stock-teleprompter` 用和上面相同的四组开关编译，结果必须一致。眼镜上的提词器是否真正可用，要等机主在设备上确认。
- Turbo IO 面板里只有“导出官方固件”和“语言”两项，没有 TMG 刷机向导。
- “导出官方固件”面板顶部显示宿主、防护和自动更新三行：
  - 防护行，绿色“已阻止 OTA 传输（已看到官方调用）”：钩子已装好，而且本次启动里至少有一次官方 App 的 `rayneonet_` 调用经过了钩子，说明官方的发送路径确实走这个钩子。Turbo IO 自己发出的调用不算。
  - 防护行，橙色“防护已安装，尚未看到官方调用”：钩子装好了，但还没有官方调用经过它。连上眼镜等一会儿，这一行会自动变绿（面板打开时每秒刷新一次）。变绿之前不要打开官方固件页面。
  - 防护行，红色“防护未生效——不要打开固件页面，也不要开始任何安装”：传输钩子没装上（找不到桥接类或方法、方法签名不对）。面板最上方同时出现红色横幅，失败原因写进 Turbo IO 的加载信息。此时不要打开官方固件页面，关闭 App 并报告。导出文件本身仍然安全，可以照常使用。
  - 自动更新行，读取官方 App 的 `*_ota_firmware_auto_update` 设置。绿色“自动更新已关闭”：明确关闭。红色“自动更新已开启：先在固件页面关闭它，再做其他操作”：开启或值不是明确的关闭。橙色“自动更新状态未记录”：没有这个设置（官方 App 把未记录当作关闭），需要打开固件页面确认开关是关的。有多个账号的设置时，按最差的一个显示。Turbo IO 只读这个设置，**从不修改**官方 App 的偏好设置。
- 面板只读查找 `Library/Application Support/ota`、`Documents/ota`、`Library/Caches/ota`、`tmp/ota`，以及这几个目录下名字像固件或升级的文件夹，最多 4 层、500 项，不跟随符号链接。每个文件显示名称、大小、修改时间、SHA-256 和 MD5，可以分享（AirDrop 或存储到文件）。不删除、不移动、不修改官方文件。
- 列表按修改时间**从新到旧**排列（文件夹和它里面的文件排在一起），名字里带 `Strix_OS_<版本>` 的会单独显示“版本”一行。目录里可能不止一个固件包，不要默认只有一个。
- SHA-256 与任何一个 Turbo 候选固件 ZIP（TMG2 到 TMG9，含被取代的版本）一致的文件，会用橙色标成“Turbo 候选固件（TMGn），不是官方固件”；同名 ZIP 被认出时，解压出的文件夹也会标出来。这些是 1.0.7 时期留下的，**不要导出它们当作官方固件**。
- 如果只找到解压后的文件夹（例如 `extracted_*`），可以“重新打包副本”。副本写在 Turbo IO 自己的目录 `Library/Application Support/TurboIOPrivateAddon/FirmwareExport/`，文件名带 `rezipped`，标注为“重新打包的副本，不是服务器原始字节”，哈希不会与服务器固件包一致。
- **预期的下载位置（问题 Q2，由 Android 1.0.10 推断并对照了 iOS 字符串，尚未在 iPhone 上实测）：** ZIP 保存在 `Library/Application Support/ota/` 下，文件名取下载地址的最后一段；最后一段为空时叫 `fota_<毫秒时间戳>.bin`。随后解压到 `ota/Strix_OS_<版本号>/`。官方 App 不会删除这个 ZIP 和文件夹（只有下载中途失败时会删掉不完整的文件）。
- **1.0.7 的残留：** 覆盖安装不清空容器，所以 `ota/` 里很可能还留着旧的 `Strix_OS_1.0.5.5.zip` 和 `Strix_OS_1.0.5.5/` 文件夹。那是 Turbo 候选固件，不是官方固件。新下载的官方包修改时间更新，会排在它们上面。
- 面板找不到时，退路是 Xcode 的 Download Container 或 `devicectl copy from`，这属于设备操作，同样需要机主当时同意。

**机主流程（每一步都在手机上由机主亲自操作）：**

1. 开始前记下眼镜状态里的 `build` 字段，确认眼镜当前是哪个 TMG。
2. 安装签好的 1.0.11 仅下载 IPA，**覆盖安装**到现有 App 上（`com.rayneo.venus.pub`），只对自己的 iPhone。绝不删除 App。
3. 打开 App，**先不要进官方固件页面**。先打开 Turbo IO →“导出官方固件”，看面板顶部：
   - 宿主行显示“RayNeo AI 1.0.11 (259) · 仅下载”，防护行是绿色的“已阻止 OTA 传输（已看到官方调用）”。防护行是红色就停下，不打开固件页面。
   - 防护行是橙色时，先连接眼镜，等它变成绿色（“已看到官方调用”）再打开官方固件页面。
   - 自动更新行是绿色“自动更新已关闭”才继续。红色或橙色时，打开官方固件页面只做一件事：把自动更新关掉（或确认它是关的），然后回到面板，确认这一行变成绿色。
4. 在官方固件页面检查更新。如果有新版本，下载它。**停在“准备安装”，绝不点“开始安装”。**
   - 如果服务器把这个版本标成强制更新，官方 App 会进入强制更新页，并自动发出开始安装的请求（类型 4，`{Mode:4}`）。防护会拒绝它，没有任何数据传到眼镜，但这个页面可能反复提示、催促安装。不理会它，不点安装，直接进行步骤 5。
   - 下载完成后，官方 App 会自动向眼镜查询电量（类型 2）和 NAND 空间（类型 3）。防护会拒绝这些帧，App 每项重试 4 次后显示“电量不足”“NAND 空间不足”或超时之类的错误。**这是预期的，无害**：ZIP 已经存在手机上，安装会话（类型 4）不会开始。不要重试，不要改设置，不要为了消掉这个错误去做任何操作，直接进行下一步。
5. 回到“导出官方固件”，点右上角的刷新按钮。选最上面、修改时间是刚才的那个新包，跳过任何标成“Turbo 候选固件”的文件。记下 ZIP 的 SHA-256 和 MD5（MD5 可以和服务器的 `apkMd5` 对照），然后分享到 Mac。
6. 在 Mac 上运行 `shasum -a 256 <文件>`，结果必须与手机上显示的 SHA-256 完全一致。不一致就不要使用这个文件。
7. 把文件存到输入目录下的 `stock-fw/<版本>/`，附上来源说明：App 1.0.11/259、日期、服务器提供的版本号、MD5 与 `apkMd5` 的对照结果。分析和固定哈希是另外的任务。**任何人都不刷这个固件。**

**回滚：** 把 C13 IPA 覆盖安装回去（`signed-20261031-0008-tmg9-c13`，安装前先核对哈希），同样不删除 App。1.0.11 可能已经迁移了容器里的数据，降级后 1.0.7 可能需要重新登录或重新配对；配对后按 OTA 刷机门槛的要求把自动更新开一次再关掉。整个流程不碰眼镜固件，所以眼镜不需要回滚。

## TMG9 candidate — current development branch

TMG9 supersedes the TMG8 section below, which stays as history. CANDIDATE-NOT-APPROVED: offline build and host evidence only, not flashed, no glasses or phone contacted. The pinned ZIP9 is in `firmware-pins.json` and `FirmwarePins.h` (they follow `firmware/`, name `TMG9`). Details and the wire/storage design: `firmware/README.md`.

TMG9 fixes the wrap (the highlight follows the animation at both ends), makes the knob step D a setting (300..600 counts per item in steps of 50, default 400) and adds caps bit 10. The glasses still report the TMG6 build name: TMG9 is proven by caps bit 10 plus the build-identity sha256 in the status `build` field, which changes from TMG8's `7fe49d041471776203ba8af03424597b53413b4b2621c8edfd69eb9b51a3ad0b` to `ae2d87a40d7460e6861036ba1f9d5458821ee7ab035d56c122aac674614db5d1` (the glasses never report the ZIP hash; the value is pinned to this ZIP9 and moves with any firmware source change). The phone sends a D-carrying SET only to glasses that reported bit 10.

**Human-only TMG8 → TMG9 checklist:**

1. Install the separately signed phone package manually and confirm the bundled candidate hash in `firmware-pins.json`. Turn RayNeo Auto Update on and then off once, and end display, navigation and music sessions before using the existing firmware wizard.
2. Download the exact bundled TMG9 candidate in RayNeo and stop at **Ready to install**; require a fresh supported version observation (at most 120 seconds old) before the single confirmation. RayNeo Auto Update and the AI updates stay off. No automatic installation or flashing.
3. After the glasses reboot, restart the phone app, refresh the status and require caps bit 10 and the build hash `ae2d87a40d7460e6861036ba1f9d5458821ee7ab035d56c122aac674614db5d1` (a status with bit 10 and any other hash is not this ZIP9).
4. Device checklist: wrap at both ends; the knob step (default 400) changed from the phone, shown Confirmed only after the status reads it back; the navigation title with no shifted arrow; music working with a route active; the test bench lyrics, card and tile states; leave the menu (open an app, go back) and check that the selection and the status line behave as on TMG8; log one turn's direction sign (stock setting 0x24).
5. Roll back manually to C12 plus ZIP8 (SHA256 `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6`; the ZIP8 flash steps in the TMG8 section below stay valid). A stored custom D makes ZIP8 ignore that layout record and fall back to the other bank or the 3-row default, so set the step back to 400 before rolling back if the layout matters. Host previews do not establish hardware acceptance.

## TMG8 candidate (superseded by TMG9; the rollback path)

TMG8 supersedes the historical candidate sections below. ZIP SHA256: `effb10b86ef7064c02512b3f3671284ea40de6349c556383eacf70f09791fbd6`; ZIP bytes: 8,819,108; ZIP MD5: `2c1a67c2d0108ecdfab139210ad67e7d`; AP size: 7,368,072 bytes (under 9.6 MB); AP SHA256: `5441188525e3fda393028694d093be713de360563ea2bb9696ec5c4c8c4a1fc1`; AP MD5: `2160d6a794be52c37797a06f173e50fe`. Two clean pinned builds are byte-identical. The audit retains 25 patch sites, the unchanged carousel raw edit, 14 untouched stock payloads, and all seven startup descriptors. This is host/build evidence only; the candidate is not approved, not flashed, and no glasses were contacted.

TMG8 adds one capability bit and one layout value to the wire (and the status `detent` field, which already existed, reads 300 instead of 600 when that bit is set; C12 accepts both): the glasses report `TD_CAP_MENU_CAROUSEL` (bit 9, `0x200`) in the status caps (`TD_CAPS_TMG8`; the build field stays `TD_BUILD_TMG6`), and the menu layout record accepts 1 (carousel) besides the grid row counts 2 and 3. The phone writes 1 only after the connected glasses' last status sample carries the bit (a SET with wire byte 7 = 1, the only non-zero use of that byte); TMG7 and TMG6 glasses never receive it, so C12 stays fully compatible with them and with TMG5 as before. After the flash the glasses still report the TMG6 build name; the proof that TMG8 is running is the caps bit 9 and the build-identity sha256 in the status `build` field, which changes from TMG7's `b86af6e1edf99fef2e1c1aa8bab8153295cb7f973ad0abe262e2f6c1b00d3bdf` to `7fe49d041471776203ba8af03424597b53413b4b2621c8edfd69eb9b51a3ad0b`. The glasses never report the ZIP hash. The same ZIP is pinned by `firmware-pins.json` and `FirmwarePins.h` (`firmware/tools/phone_pins.py`, name `TMG8` read from `firmware/RELEASE`). Rollback is C11 plus ZIP7 (ZIP7 rejects a stored carousel value and loads the last saved grid layout, 3 rows if none was ever saved; until ZIP7 is flashed back, C11's status and knob screens do not read TMG8 glasses, and the C11 OTA wizard, which does not use that sample, still flashes). Details: `firmware/README.md`.

**Human-only TMG7 → TMG8 checklist:**

1. Install the separately signed C12 package manually and confirm the bundled candidate hash above. Turn RayNeo Auto Update on and then off once, and end display/navigation/music sessions before using the existing firmware wizard.
2. Download the exact bundled TMG8 candidate in RayNeo and stop at **Ready to install**. Require a fresh supported version observation (at most 120 seconds old) before the existing single confirmation. No automatic worker installation or flashing is authorized.
3. After the glasses reboot, restart the phone app and check the new menu and pages: the carousel (80 / 48 / 36 px icons and its slide), the knob (one item per 300 counts, wrap at both ends), the live tile status line and grid dots, the navigation title in the menu while a route is live and the Navigation page is closed, the dashboard card, and long lyrics. The device checks listed in the TMG8 README remain open.
4. Roll back manually to C11 plus ZIP7 using the same guarded OTA process. Host previews do not establish hardware acceptance.

**Music while navigating (C13, phone only; works with TMG8 glasses).** Navigation and music no longer exclude each other on the phone. Earlier builds refused to send music whenever a navigation session was active, which also covered the TMG8 background route (page closed, route kept), so the music tile found the phone silent. Now:

- Music OPEN is sent whenever no firmware stage is running. A glasses answer of BUSY to OPEN (the navigation page is on screen) or NO_SESSION to CLOCK, COVER, LYRICS or CLOSE (the music page is closed) puts the music bridge to rest: not failed, no retry loop. The glasses' own Resume request reopens it. BAD, STALE, transport errors and any other result still stop the bridge.
- Navigation (TNV1) and music (TMU1) share one native file link, so only one file is in flight at a time. Music waits while a navigation file is in flight. Navigation gives music one non-urgent slot (a pose, a passing line or a routine UPDATE) per 1.4 s window, for at most 0.4 s, when music has a packet ready; STOP and urgent UPDATEs (a new turn icon, mode or road text) never yield, and the 8 s navigation acknowledgement deadline is unchanged. One exception: after a transport failure (no acknowledgement within the deadline, or a refused submit) the failed side stops claiming the link and does not send again until it is reopened, because the native file it left behind may never report back; the other side may start its own file while that stale one is still in the native layer.
- The reverse gate stays: starting navigation while the glasses music page is open is refused, because the glasses refuse that START too. The phone now says so (status note and the glasses alert) instead of failing silently: close the music page on the glasses, then start navigation again.
- OTA is unchanged: a firmware stage still blocks both, and the OTA guard still wants navigation and music idle.

## TMG7 candidate (superseded by TMG8)


TMG7 supersedes the historical candidate sections below. ZIP SHA256: `6b06d0dd3124ac1f86c91e0879908f9bfe129a2051cf0b619d5b0b664bc3c0aa`; ZIP bytes: 8,814,600; AP size: 7,360,584 bytes; AP SHA256: `5213d2f3a29858ff2e04c770b3ae4501615c448158e354173b39cd2345501a67`; AP MD5: `55458db47aaa5e69e5ef95f72e0b611e`. Two clean pinned builds are byte-identical. The audit retains 25 patch sites, the unchanged carousel raw edit, 14 untouched stock payloads, and all seven startup descriptors. This is host/build evidence only; the candidate is not approved, not flashed, and no glasses were contacted. After the flash the glasses still report the TMG6 firmware name and capabilities (TD_BUILD_TMG6, TD_CAPS_TMG6; the wire protocol is unchanged by design), so the status screen reads `firmware: TMG6` before and after. The proof that TMG7 is running is the status `build` field, the build-identity sha256, which changes from TMG6's `83b82fab9fe9356de62570deff5878b9cfc292b3037998088664e87bd90d8644` to `b86af6e1edf99fef2e1c1aa8bab8153295cb7f973ad0abe262e2f6c1b00d3bdf` (shown on the "Firmware and build" row).

TMG7 re-lays navigation, music, focus timer, the main menu, the camera hint and the mini-app runtime to the design system. The wire protocol, capability masks and firmware name (TD_BUILD_TMG6, TD_CAPS_TMG6) are unchanged, so C11 stays fully compatible with TMG6 glasses (and TMG5 as before) and pins only the exact TMG7 ZIP for the wizard. Only the build-identity sha256 in the status `build` field changes with the flash (see above); the glasses never report the ZIP hash.

**Human-only TMG6 → TMG7 checklist:**

1. Install the separately signed C11 package manually and confirm the bundled candidate hash above. Turn RayNeo Auto Update on and then off once, and end display/navigation/music sessions before using the existing firmware wizard.
2. Download the exact bundled TMG7 candidate in RayNeo and stop at **Ready to install**. Require a fresh supported version observation (at most 120 seconds old) before the existing single confirmation. No automatic worker installation or flashing is authorized.
3. After the glasses reboot, restart the phone app and check each re-laid page: map clipped at the lens edge, music lyrics on one or two lines, focus timer, the menu caret and focused name, the transient camera hint, and mini-app caret focus. The 16 px lens-mid text legibility and the caret visibility are device checks.
4. Roll back manually to C10 plus ZIP6, or C9 plus ZIP5, using the same guarded OTA process. Host previews do not establish hardware acceptance.

## TMG6 candidate (superseded by TMG7)

TMG6 supersedes the historical candidate sections below. ZIP SHA256: `a134c0f9d8550cdd5b53559e4857e27ca92ec8b168543d2c357cbc1e3fbe4d6e`; AP size: 7,357,832 bytes; AP MD5: `55d933ad07b474535ed0389b09d0ddf3`. Two clean pinned builds are byte-identical. The audit retains 25 patch sites, the unchanged carousel raw edit, 14 untouched stock payloads, and all seven startup descriptors. This is host/build evidence; device acceptance remains NOT RUN.

C10 remains compatible with TMG5 glasses: the new Passing message requires navigation capability mask `0x08`. TMG6 shows the full forward route within the visible map, a five-pixel route with a seven-pixel black halo, a larger fixed heading-up car marker, a fixed full-road-name line, smooth stock-family scale text, and three non-overlapping lyric slots capped at two lines each. Phone word segmentation supplies safe ellipsis boundaries. Host EN/ZH previews use macOS surrogate fonts; actual stock font appearance remains a human device check. Knob observation: approximately 2000 raw counts per full rotation; wheel behavior is unchanged.

**Human-only TMG5 → TMG6 checklist:**

1. Install the separately signed C10 package manually and confirm the bundled candidate hash above. Turn RayNeo Auto Update on and then off once, and end display/navigation/music sessions before using the existing firmware wizard.
2. Download the exact bundled TMG6 candidate in RayNeo and stop at **Ready to install**. Require a fresh supported version observation (at most 120 seconds old) before the existing single confirmation.
3. Confirm exactly once in the existing wizard, keep both devices powered and connected, and wait for the glasses to reboot. No automatic worker installation or flashing is authorized.
4. Restart the phone app after flashing. Check TMG6 identity, full-route pixels before each of two turns, EN/ZH Passing fallback and long-name ellipsis, scale/distance readability, marker centering, and long EN/ZH lyrics. Recheck tiles, captions, speech speed, and existing music controls.
5. Roll back manually to C9 plus ZIP5, or C8 plus ZIP4, using the same guarded OTA process. Signed packages and host previews do not establish hardware acceptance.

OTA routing, hash/freshness checks, the single-confirmation policy, boot/NAND paths, and wheel scaling remain unchanged. The FW6 retained-call checker is byte-identical to FW5, including only the existing `tm_rotate` exception.

## TMG5 candidate — current development branch

TMG5 supersedes the historical candidate sections below. The exact candidate ZIP SHA256 is `6705bf4d164178943018d55ac882cf796bbc255f186d0be509ecb2f798ede0ef`; AP size is 7,355,400 bytes and AP MD5 is `8ece02af435fb8643c444ca5d412a2fe`. Two clean builds match byte for byte, with 25 existing patch sites and 14 unchanged stock payloads. This is build/host evidence; physical acceptance remains unrun.

The phone remains compatible with TMG4 glasses. Tile actions now work during reordering and display acknowledgement/failure feedback; Reset also saves. Read-only status accepts safe supported app states, while knob calibration explains the main-menu prerequisite and releases a refused lease. Initial navigation geometry precedes turn updates; TMG5 advertises bounded correction/heading smoothing, a six-pixel route, and static square music artwork with wheel/tap control hints. Background roads are filtered on the phone. The existing music commands still invoke the phone's Spotify controls. Speech defaults to 1.2× with five persisted choices for both English and Chinese, and explicitly confirmed idle captions no longer block microphone selection because of a missing template or stopped session.

**Human-only TMG4 → TMG5 checklist:**

1. Install the C9 phone package only after its signing/build review. Turn RayNeo Auto Update on and then off once.
2. Download the bundled exact TMG5 candidate in RayNeo and stop at **Ready to install**.
3. Obtain a version read within two minutes, then use the existing single confirmation. This worker never flashes or talks to glasses.
4. After reboot, restart the phone app. Check all 13 tiles and Camera, reorder/hide/save/reset feedback and persistence, language, read-only status, main-menu knob guidance, and one-turn measurement.
5. Check simulated and real-GPS initial map timing, backward/forward corrections, turns and route contrast; check music artwork and wheel/tap controls, both speech languages at each speed, and caption source changes after stopping. Verify active navigation, display and OTA still block conflicting caption changes.
6. Roll back with **C8 plus ZIP4**, or **C5 plus ZIP2**, using the matching old phone package and manual flash flow. C9 accepts only ZIP5; rollback and hardware recovery are not verified here.

The firmware's source/input identity is separate from the ZIP hash. Runtime capabilities are accepted only for the matching TMG4/TMG5 family. OTA host guards, hash/freshness policy and single-confirmation behavior are unchanged. The sole preservation-check exception is the user-approved removal of `tm_rotate`, applied and committed by the coordinator in FW5 only; earlier firmware trees remain frozen.

## TMG4 candidate — current development branch

This branch offers only **TMG4 CANDIDATE-NOT-APPROVED**, bundled as `TurboWeReadCandidate.zip`. It includes the unflashed TMG3+TMG4 delta; deviceIO=false and physical acceptance is unrun. Firmware source, formats and rebuild: [`firmware/README.md`](../../firmware/README.md) (this exact release is the git tag `fw/tmg4`).

| Payload | Bytes | SHA-256 | MD5 |
| --- | ---: | --- | --- |
| ZIP | 8809015 | `aa387b37ece2092d50721bcc3409984f7bd0d650aad4b7b249aceba515161126` | `f72c9a3a79ab02d968dc1415ee117509` |
| AP | 7353800 | `0d6a3ec1d4aac08351afa6b60031c96f4e3904887a61a62def3da561f6c0c02b` | `ea89c1d953fff0b0ffe932c2ed2b5c46` |

TMG4 adds persistent custom tile order/visibility (stock0–6 fixed, Camera always visible,8–13 active entries), reboot-persistent language with source2 confirmation, read-only runtime status and a30-second one-turn knob estimate. The600-unit detent heuristic is unchanged. Legacy removed-app replies and the outbound legacy POSE fallback are dropped; this phone build does not fully drive TMG2. The existing flash wizard still accepts a fresh validated TMG2-era version reply and uses exactly the TMG4 ZIP; the host/freshness/hash/slice policy and single confirmation remain unchanged.

**Human-only TMG2→TMG4 checklist:**

1. Keep the TMG2-pinned C5 phone IPA and immutable TMG2 ZIP for rollback. Install C8 by hand only after its separate review.
2. Back up phone app data, charge glasses above50%, open their launcher, and finish active recording/navigation/music/file work. In RayNeo Software version, turn Auto Update **on then off once** so its setting exists.
3. In Turbo › Glasses › Glasses firmware, pass the package/source/protection/settings checks and open the15-minute download window. Download in RayNeo and stop at **Ready to install**. Return to Turbo and require an exact directory match.
4. Read the glasses version in RayNeo and return within **120seconds**. Accept the wizard's **one confirmation**, then manually tap Start install in RayNeo. Authorization itself starts no flash.
5. After glasses reboot/reconnect, fully close and restart the phone app. Verify13 default tiles; save and reboot reordered/hidden tiles and language; inspect status; measure one full knob turn; test POSE2 in a dead zone, all retained tiles and Spotify.
6. For rollback, install the earlier **C5** phone package, then manually flash the matching **TMG2 ZIP**. C8 accepts only TMG4; it cannot authorize a TMG2 rollback. Recovery has not been tested by this worker.

```sh
python3 test.py --firmware /absolute/path/to/exact-TMG4-CANDIDATE-NOT-APPROVED.zip --app107 /absolute/original/Runner.app --patched-app /absolute/patched/Runner.app
```

The default packager identity is `TMG4` (an explicit `--experimental-ota TMG4` is optional); older candidate names and changed hashes are rejected. All instructions and acceptance results below describe earlier WP6/WP5/publication snapshots. They do not establish TMG4 device acceptance and do not override this section.


## WP6: unflashed TMG3 candidate

**The morning flash is a human decision.** WP6 offers TMG3, not a device-accepted upgrade: `StrixOS-1.0.5.5-TurboIO-TMG3-CANDIDATE-NOT-APPROVED.zip`, 8803177 bytes, SHA-256 `45595fe26086aaeb64e4eaa1243d09f2a7ec8388d52661d34a0c439bbd6de274`. Its AP is 7344072 bytes, SHA-256 `b54a28a628112c2b548393328528c2f7a19e727741f1fd6ede35cfbee4290c52`, MD5 `28d26bb9965e2648ab514e02d4708957`. The package still uses resource name `TurboWeReadCandidate.zip` and the frozen APP107 routing marker. Packaging/installing the phone app never starts or authorizes a flash. The 2026-10-19 TMG2 acceptance record below is historical; `tmg3FlashAcceptedOnDevice` is false.

The existing three-step wizard and single destructive confirmation below are unchanged. TMG2 glasses keep normal phone functionality, receive legacy POSE only and ignore TLG1. Check the new phone package with TMG2 still installed before making a separate TMG3 decision.

**Rollback requires an earlier phone build.** This build accepts only the TMG3 ZIP, so it cannot authorize a TMG2 reflash. Before a human chooses TMG3, keep the TMG2-pinned C5 phone IPA at `~/projects/personal/turboio-inputs/signed-20261027-1443-wp7c-c5/TurboIO-local-only.ipa`, or C4 at `~/projects/personal/turboio-inputs/signed-20261027-1231-wp5-c4/TurboIO-local-only.ipa`, with the immutable TMG2 ZIP. A human must install that earlier phone build before attempting the matching TMG2 rollback; no rollback was performed here.

2026-10-19 · [构建与签名](README.md) · [TMG2 固件下载](https://github.com/Turbo1123/Turbo-IO/releases/tag/navs3-tmg2-20261019)

## 适用范围与风险

本版开放的是 **APP107-OTA / 雷鸟 1.0.7（230）→ 固定 TMG2（基于 Strix OS 1.0.5.5）**。iPhone 17 Pro Max 已实刷成功，不代表任意宿主、机型或候选都能使用。已装 TMG2 且功能正常，不必重复刷。

高风险研究固件，非开发者请勿尝试。不保证回滚、恢复或救砖。只有 AP 内容经过自定义修改，**不代表完整官方 OTA 仅写 AP**。不要改版本号或校验来绕过保护，不混用 Android / 1.0.6 的包与授权。

公开版只提供源码与构建工具；自行取得合法未加密原厂输入、匹配签名和设备授权，按 README 打包。新打包器默认加入专用升级通道，**不自动开始下载或刷写**；旧 APP107 禁用 OTA 包必须重新构建，改 README 不会更新已装 App。

## Firmware wizard (English)

Open **Turbo › Glasses › Glasses firmware**. The wizard shows the firmware name from the app's `TIOExperimentalOTABuild` key. With that key set to `TMG3`, it names TMG3. WP6 now pins the exact TMG3 bytes and sets the Info value to TMG3; the bundled filename remains `TurboWeReadCandidate.zip`. The earlier WP5 C4 package was TMG2-pinned. Opening the wizard does not start an installation.

1. **Check.** Back up the phone App data. Keep the glasses above 50% charge, on their home screen and connected; finish recording, navigation, music and other active tasks. The Package row checks the candidate, Source checks the local download service, Protection checks the host gate, Auto Update checks RayNeo's setting, and Version checks the recent read from the glasses. On a fresh install, open **RayNeo › Glasses › Software version** and turn Auto Update **on, then off once** so RayNeo saves the setting. The wizard's **Fix** can turn it off only when an existing, recognizable setting is present; if the setting is missing or unknown, use RayNeo. Do not continue while a required check fails.
2. **Download.** Open the wizard's 15-minute download window. In **RayNeo › Glasses › Software version**, download the update and stop at **Ready to install**; do not tap Start install yet. Return to Turbo and wait for the downloaded directory check to pass. RayNeo may reuse a matching verified cache, so a download request count of zero alone does not show failure. If the window expires or the directory does not match, stop and repeat the checks.
3. **Install.** Have RayNeo read the glasses version again and return to Turbo **within 120 seconds**. Check that the version read is fresh and the downloaded directory still matches. Read and accept the wizard's **single confirmation** to allow one transfer. Authorization alone does not start a flash: return to **Ready to install** in RayNeo and manually tap **Start install** there. Wait for RayNeo to finish and the glasses to restart and reconnect. Then fully close and relaunch RayNeo; check its result and the wizard status before using the glasses normally. If the result is unclear, stop rather than repeat the transfer.

## 固件向导（中文）

打开 **Turbo › 眼镜 › 眼镜固件**。向导从 App 的 `TIOExperimentalOTABuild` 键读取固件名称；该键为 `TMG3` 时显示 TMG3。WP6 已固定本次 TMG3 的字节校验值，Info 值为 TMG3；资源名仍为 `TurboWeReadCandidate.zip`。历史 WP5 C4 包固定的是 TMG2。打开向导不会开始安装。

1. **检查。** 先备份手机 App 数据。眼镜电量保持 50% 以上、停在首页并保持连接，结束录音、导航、音乐等正在进行的任务。「固件包」检查候选包，「来源」检查本机下载服务，「保护」检查宿主门禁，「自动更新」检查雷鸟设置，「版本」检查最近一次眼镜版本回读。首次安装时，在 **RayNeo › 眼镜 › 软件版本**中把「自动更新」**先打开、再关闭一次**，让 RayNeo 保存该设置。仅当已有可识别的设置键时，向导的「修复」才能将其关闭；设置缺失或状态未知时请在 RayNeo 中操作。必需检查未通过时不要继续。
2. **下载。** 在向导中开启 **15 分钟**下载窗口。到 **RayNeo › 眼镜 › 软件版本**下载更新，停在「**软件就绪**」，先不要点「开始安装」。返回 Turbo，等待解压目录校验通过。RayNeo 可能复用已校验且一致的缓存，因此下载请求数为 0 本身不代表失败。窗口过期或目录不匹配时，停止并重新检查。
3. **安装。** 让 RayNeo 再次读取眼镜版本，并在 **120 秒内**返回 Turbo。确认版本回读仍有效、下载目录仍匹配。阅读向导的**单次确认**，允许一次传输。授权本身不会开始刷写：回到 RayNeo 的「软件就绪」页，**手动点「开始安装」**。等待 RayNeo 完成、眼镜重启并重新连接。随后彻底关闭并重新打开 RayNeo，核对官方结果和向导状态，再恢复日常使用。结果不明时停止，不要重复传输。

本版不是原厂恢复工具：原厂 ZIP 或其他候选会被拒绝。恢复请读[原厂固件说明](../../firmware-research/strix-1.0.5.5/README.md)，使用独立匹配且经过验证的工具链。

## 本次实测证据与边界

- 用户完成实刷；官方记录传输 100%、安装 succeeded / version_matched，重连后 Strix OS 1.0.5.5 / idle / confirmed。
- 236 个通过校验的分片共 11940662 字节，覆盖本次官方请求的 6 个负载，含完整 AP 7408584 字节；不声称 15 个负载均重新传输。
- 刷后新手机进程回读：授权 0、已开始 0、下载窗口关闭。
- 本轮使用逐字节校验一致的官方缓存，未另做网络重新下载实测。公开脱敏源独立编译、回归和本地签名检查，与私用实测 IPA 不逐字节相同。
- 私人日志、Cookie、Key、签名材料和 IPA 不公开；其他机型、账号与所有后台场景未逐一验证。

## Why official updates stay redirected (decision 2026-10)

- package.mjs patches two inspected App.framework route records through patch-route.mjs, and ExperimentalOTAFeed.m answers on 127.0.0.1. For packageType=app, and for firmware unless a pinned TMG archive is armed, it returns no update. This prevents the official app from offering stock Strix OS, which would overwrite TMG2/TMG3 and remove the Turbo glasses features.
- A build without the route marker fails TIOOTA107HostMatches in OTAHost.h. The flash gate then refuses every business-9 frame, and the flash wizard cannot install Turbo firmware updates.
- Official app updates do not apply to this re-signed build. The App Store does not update it, and validateHost in package.mjs pins 1.0.7/230 exactly; a new RayNeo version therefore needs a new addon port.

To return to stock: delete the Turbo build, reinstall RayNeo AI from the App Store, and accept the official firmware update there. No separate un-redirected build is shipped.
