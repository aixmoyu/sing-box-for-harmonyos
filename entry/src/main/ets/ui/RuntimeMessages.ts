/**
 * Runtime message boundary for strings produced by repositories, domain
 * validation, the VPN coordinator and the native extension.
 *
 * Domain errors intentionally remain stable Chinese strings so existing
 * contracts do not need UI concerns. Every user-visible runtime sink passes
 * through this catalog. Unknown Chinese/native errors fail closed to a safe,
 * localized category instead of leaking credentials or a half-translated
 * implementation detail into the English UI.
 */

function hnaCode(value: string): string {
  const match: RegExpMatchArray | null = value.match(/HNA-[A-Z-]+/)
  return match ? match[0] : ''
}

function hasHan(value: string): boolean {
  return /[\u3400-\u9FFF]/.test(value)
}

function exactEnglish(value: string): string {
  switch (value) {
    case '尚未添加订阅': return 'No subscription yet'
    case '未选择节点': return 'No node selected'
    case '暂未统计': return 'No data yet'
    case '粘贴一个订阅地址，解析支持的节点、基础规则和 DNS':
      return 'Paste a subscription URL to parse supported nodes, basic rules and DNS.'
    case '测试中…': return 'Testing…'
    case '失败': return 'Failed'
    case '等待连接': return 'Ready to connect'
    case '正在检查 VPN 状态': return 'Checking VPN status'
    case 'VPN 状态尚未确认': return 'VPN status is not confirmed'
    case '核心状态暂不可读，不会解锁运行配置': return 'Core status is unreadable. Runtime settings remain locked.'
    case '正在下载并解析订阅…': return 'Downloading and parsing subscription…'
    case '本地订阅读取失败；旧数据未被覆盖': return 'Could not load local subscriptions. Existing data was not changed.'
    case '订阅已保存，节点列表已更新': return 'Subscription saved. The node list is up to date.'
    case '订阅更新成功': return 'Subscription updated.'
    case '订阅解析失败': return 'Could not parse the subscription.'
    case '订阅更新失败': return 'Could not update the subscription.'
    case '订阅名称已保存': return 'Subscription name saved.'
    case '订阅名称保存失败': return 'Could not save the subscription name.'
    case '订阅已删除': return 'Subscription removed.'
    case '删除确认窗口打开失败': return 'Could not open the removal confirmation.'
    case '删除失败，原订阅仍保留': return 'Removal failed. The existing subscription was kept.'
    case '请等待当前 VPN 操作完成后再重命名订阅': return 'Wait for the current VPN operation before renaming the subscription.'
    case '运行中只能切换当前订阅的节点': return 'While connected, nodes can be switched only inside the active subscription.'
    case '当前为直连模式，不经过代理；已保存为下次代理连接的首选节点':
      return 'Direct mode bypasses the proxy. This node is saved for the next proxy connection.'
    case '下次代理连接的首选节点保存失败': return 'Could not save the preferred node for the next proxy connection.'
    case 'VPN 运行协调器尚未就绪': return 'The VPN service is still initializing. Try again shortly.'
    case '运行节点已切换': return 'Runtime node switched.'
    case '本次运行节点已切换，但首选节点保存失败；下次连接可能恢复旧选择':
      return 'The runtime node switched, but the preference was not saved. The next connection may restore the previous node.'
    case '手动节点已切换': return 'Manual node selected.'
    case '自动优选偏好节点已切换': return 'Auto-select preference updated.'
    case '故障转移首选节点已切换': return 'Failover primary node updated.'
    case '已设置自动优选的偏好节点': return 'Auto-select preference updated.'
    case '已设置故障转移首选节点': return 'Failover primary node updated.'
    case '自动优选由 URLTest 决定，运行中不能手动指定节点；请先切换为手动模式':
      return 'Auto-select is controlled by URLTest while connected. Switch to Manual before choosing a node.'
    case '故障转移由核心健康检查决定，运行中不能手动指定节点；请先切换为手动模式':
      return 'Failover is controlled by core health checks while connected. Switch to Manual before choosing a node.'
    case '核心未确认新的运行节点': return 'The core did not confirm the new runtime node.'
    case '运行节点切换失败': return 'Could not switch the runtime node.'
    case '节点选择保存失败': return 'Could not save the node selection.'
    case '请先断开 VPN，再进行服务器 TCP 可达性测试':
      return 'Disconnect VPN before testing direct server TCP reachability.'
    case '请先添加并选择订阅': return 'Add and select a subscription first.'
    case '服务器 TCP 可达性测试完成': return 'Server TCP reachability test completed.'
    case '代理 URLTest 需要先连接 VPN；未连接时可使用 TCP 延迟测试':
      return 'Connect VPN before proxy URLTest. Use TCP latency while disconnected.'
    case '当前为直连模式，流量不经过代理，代理组 URLTest 不适用':
      return 'Proxy URLTest is unavailable because Direct mode bypasses the proxy.'
    case '请先选择一个节点': return 'Select a node first.'
    case '代理 URLTest 完成': return 'Proxy URLTest completed.'
    case '代理 URLTest 失败': return 'Proxy URLTest failed.'
    case '节点代理测速需要先连接 VPN': return 'Connect VPN before testing a node through the proxy.'
    case '当前为直连模式，流量不经过代理，节点代理测速不适用':
      return 'Node proxy testing is unavailable because Direct mode bypasses the proxy.'
    case '节点代理测速失败': return 'Node proxy test failed.'
    case '批量代理测速需要先连接 VPN': return 'Connect VPN before testing all nodes through the proxy.'
    case '当前为直连模式，流量不经过代理，批量代理测速不适用':
      return 'Batch proxy testing is unavailable because Direct mode bypasses the proxy.'
    case '批量代理 URLTest 完成': return 'Batch proxy URLTest completed.'
    case '请先连接 VPN，再测试当前网络的网站可用性':
      return 'Connect VPN before testing website availability on the current network.'
    case '网站可用性测试完成': return 'Website availability tests completed.'
    case '请先连接 VPN，再检测当前出口 IP': return 'Connect VPN before checking the current egress IP.'
    case '当前出口 IP 检测完成': return 'Egress IP check completed.'
    case '出口 IP 检测失败': return 'Egress IP check failed.'
    case '出口 IP 检测失败，请稍后重试': return 'Egress IP check failed. Try again later.'
    case '出口检测未返回 IP': return 'The egress service did not return an IP address.'
    case '请等待当前配置保存完成': return 'Wait for the current settings save to finish.'
    case '请等待本地配置恢复完成': return 'Wait for local settings to finish restoring.'
    case '连接服务仍在初始化，请稍后重试': return 'The VPN service is still initializing. Try again shortly.'
    case '正在安全停止可能残留的 VPN/TUN…': return 'Safely stopping any remaining VPN/TUN…'
    case 'VPN 已安全停止，可以重新连接': return 'VPN stopped safely. You can reconnect now.'
    case 'VPN 安全停止失败': return 'Could not safely stop VPN.'
    case '正在停止核心并销毁 TUN…': return 'Stopping the core and destroying TUN…'
    case 'VPN 已断开': return 'VPN disconnected.'
    case 'VPN 断开失败': return 'VPN disconnect failed.'
    case '请先添加订阅并选择节点': return 'Add a subscription and select a node first.'
    case '当前订阅依赖尚未下载的远程规则集；请先使用全局代理或直连模式':
      return 'This subscription needs remote rule sets that are not downloaded. Use Global or Direct mode.'
    case '当前订阅包含尚未支持的规则类型；请先使用全局代理或直连模式':
      return 'This subscription contains unsupported rules. Use Global or Direct mode.'
    case '请先校验并保存自定义 DNS': return 'Validate and save the custom DNS endpoint first.'
    case '运行配置不完整': return 'Runtime configuration is incomplete.'
    case '正在生成运行配置，随后请求系统 VPN…': return 'Preparing runtime configuration before requesting system VPN…'
    case '正在请求系统 VPN；已授权时不会再次弹窗':
      return 'Requesting system VPN. The prompt is not repeated after permission is granted.'
    case 'VPN/TUN 已连接': return 'VPN/TUN connected.'
    case 'VPN 连接失败': return 'VPN connection failed.'
    case 'VPN 启动请求未被系统接受，未创建 TUN': return 'The system rejected VPN startup. No TUN was created.'
    case '系统 VPN/TUN 正在接管设备流量': return 'System VPN/TUN is routing device traffic.'
    case '连接服务尚未就绪': return 'The VPN service is not ready.'
    case '安全锁定': return 'Safety lock'
    case '默认使用加密 DNS；所有 DNS 请求由 TUN 交给 sing-box 处理':
      return 'Encrypted DNS is enabled and handled by sing-box inside TUN.'
    case '请输入 HTTPS DoH 或 TLS DoT 地址并保存；当前连接仍使用原 DNS':
      return 'Enter an HTTPS DoH or TLS DoT endpoint and save it. The current DNS remains active.'
    case '自定义加密 DNS 已保存并应用': return 'Custom encrypted DNS saved and applied.'
    case '自定义加密 DNS 已保存': return 'Custom encrypted DNS saved.'
    case 'DNS 设置保存失败': return 'Could not save DNS settings.'
    case 'DNS 地址不正确': return 'The DNS endpoint is invalid.'
    case '请输入自定义 DNS 地址': return 'Enter a custom DNS endpoint.'
    case 'DNS 地址过长': return 'The DNS endpoint is too long.'
    case 'DNS 地址包含不允许的字符': return 'The DNS endpoint contains unsupported characters.'
    case '自定义 DNS 仅支持 https:// DoH 或 tls:// DoT': return 'Custom DNS supports only https:// DoH or tls:// DoT.'
    case 'DoT 地址不能包含路径': return 'A DoT endpoint cannot contain a path.'
    case 'DNS 地址缺少有效主机名': return 'The DNS endpoint needs a valid host name.'
    case 'DNS IPv6 地址格式不正确': return 'The DNS IPv6 address is invalid.'
    case 'DNS 地址端口格式不正确': return 'The DNS port format is invalid.'
    case 'IPv6 DNS 地址需要使用方括号': return 'Wrap an IPv6 DNS address in square brackets.'
    case 'DNS 主机名或 IP 地址不正确': return 'The DNS host name or IP address is invalid.'
    case 'DNS 端口必须是数字': return 'The DNS port must contain digits only.'
    case 'DNS 端口必须在 1 到 65535 之间': return 'The DNS port must be between 1 and 65535.'
    case '网络设置读取失败': return 'Could not load network settings.'
    case '网络设置存储尚未就绪': return 'Network settings storage is not ready.'
    case '网络设置版本无法识别，已保留原文件': return 'The network settings version is unsupported. The original file was kept.'
    case '应用接管范围不是有效 JSON': return 'The application tunnel scope is not valid JSON.'
    case '应用接管范围数据不完整': return 'The application tunnel scope is incomplete.'
    case '应用白名单数据不完整': return 'The application allowlist is incomplete.'
    case '同一应用只能加入白名单一次': return 'An app can be added to the allowlist only once.'
    case '仅所选应用模式至少需要加入一个应用': return 'Only selected apps mode requires at least one app.'
    case '网络助手自身不能加入应用白名单': return 'Network Assistant itself cannot be added to its VPN allowlist.'
    case '应用包名长度必须在 7 到 128 个字符之间': return 'The app bundle name must contain 7 to 128 characters.'
    case '应用包名必须是至少三段的反向域名': return 'The app bundle name must be a reverse domain with at least three labels.'
    case '应用包名不能包含空段': return 'The app bundle name cannot contain an empty label.'
    case '应用包名第一段必须以字母开头': return 'The first app bundle label must start with a letter.'
    case '应用包名后续分段必须以字母或数字开头': return 'Each following app bundle label must start with a letter or digit.'
    case '应用包名分段必须以字母或数字结尾': return 'Each app bundle label must end with a letter or digit.'
    case '应用包名只能包含字母、数字、下划线和点': return 'The app bundle name may contain only letters, digits, underscores and dots.'
    case '全部应用进入 VPN': return 'All apps will enter VPN.'
    case '应用已加入 VPN 白名单': return 'The app was added to the VPN allowlist.'
    case '应用已移出 VPN 白名单': return 'The app was removed from the VPN allowlist.'
    case '本地规则已保存并应用': return 'Local rule saved and applied.'
    case '本地规则已保存；切换到规则模式后应用': return 'Local rule saved. It applies after switching to Rule mode.'
    case '本地规则已删除': return 'Local rule removed.'
    case '本地规则已删除；当前路由无需重连': return 'Local rule removed. The current route did not need to reconnect.'
    case '已删除；当前路由未重启': return 'Removed without restarting the current route.'
    case '删除已生效': return 'Removal applied.'
    case '请输入域名': return 'Enter a domain.'
    case '域名规则过长': return 'The domain rule is too long.'
    case '域名规则只能填写完整域名，不支持网址、路径或通配符':
      return 'Enter a domain only. URLs, paths and wildcards are not supported.'
    case '域名格式不正确': return 'The domain format is invalid.'
    case '请输入 CIDR 网段': return 'Enter an IP CIDR range.'
    case 'CIDR 网段格式不正确': return 'The CIDR format is invalid.'
    case 'CIDR 必须包含有效前缀长度': return 'CIDR must include a valid prefix length.'
    case 'CIDR 前缀不能包含前导零': return 'The CIDR prefix must not contain leading zeros.'
    case 'IPv4 CIDR 前缀必须在 0 到 32 之间': return 'An IPv4 CIDR prefix must be between 0 and 32.'
    case 'IPv6 CIDR 前缀必须在 0 到 128 之间': return 'An IPv6 CIDR prefix must be between 0 and 128.'
    case 'CIDR IP 地址格式不正确': return 'The CIDR IP address is invalid.'
    case '本地规则仅支持完整域名、域名后缀和 CIDR':
      return 'Local rules support exact domains, domain suffixes and CIDR only.'
    case '本地规则目标仅支持代理、直连或拒绝':
      return 'A local rule target must be Proxy, Direct or Reject.'
    case '本地规则数据不完整': return 'The local rule data is incomplete.'
    case '本地规则不能重复': return 'Duplicate local rules are not allowed.'
    case '同一匹配条件只能配置一次': return 'The same match condition can be configured only once.'
    case '规则保存失败': return 'Could not save the local rule.'
    case '订阅存储尚未就绪': return 'Subscription storage is not ready.'
    case '订阅数据包含无法识别的记录，已保留原文件':
      return 'The subscription data contains an unrecognized record. The original file was kept.'
    case '订阅数据版本无法识别，请先导出后重置':
      return 'The subscription data version is unsupported. Export the data before resetting it.'
    case '订阅地址必须使用 https://': return 'The subscription URL must use https://.'
    case '订阅包含节点凭据，首版只允许 https:// 地址': return 'Subscription URLs containing credentials are not accepted. Use https://.'
    case '订阅下载失败，请检查地址、网络或服务状态':
      return 'Subscription download failed. Check the URL, network and provider status.'
    case '无法安装 HTTPS 重定向安全检查，已拒绝下载订阅':
      return 'HTTPS redirect safety validation could not be installed. The subscription download was refused.'
    case '订阅重定向试图离开 HTTPS，已拒绝下载':
      return 'The subscription redirect attempted to leave HTTPS. The download was refused.'
    case '无法确认订阅最终地址仍为 HTTPS，已拒绝下载':
      return 'The final subscription URL could not be confirmed as HTTPS. The download was refused.'
    case '订阅服务器没有返回文本配置': return 'The subscription server did not return a text configuration.'
    case '订阅内容超过 4 MiB 安全上限': return 'The subscription exceeds the 4 MiB safety limit.'
    case '订阅内容为空': return 'The subscription is empty.'
    case '订阅中没有可用节点': return 'The subscription contains no usable nodes.'
    case '订阅包含无效的 Base64 字符': return 'The subscription contains invalid Base64 data.'
    case 'VMess alterId 必须是非负整数': return 'VMess alterId must be a non-negative integer.'
    case '节点链接缺少协议名': return 'The proxy link is missing a protocol name.'
    case 'IPv6 地址缺少右方括号': return 'The IPv6 address is missing its closing bracket.'
    case '节点链接缺少端口': return 'The proxy link is missing a port.'
    case 'Hysteria2 obfs 当前版本未完整支持，已跳过':
      return 'This Hysteria2 obfuscation mode is not fully supported and was skipped.'
    case '没有可用于生成配置的节点': return 'No node is available for runtime configuration.'
    case '选择的节点已经失效，请重新选择': return 'The selected node is no longer available. Select another node.'
    case 'IPv6 已关闭，DNS 上游不能使用 IPv6 地址':
      return 'An IPv6 DNS upstream cannot be used while IPv6 is disabled.'
    case '新运行配置无法生成': return 'Could not generate the new runtime configuration.'
    case '一次运行配置事务只能修改订阅或网络设置之一':
      return 'One runtime transaction can change either the active subscription or network settings, not both.'
    case '核心未确认原连接已恢复': return 'The core did not confirm that the previous connection was restored.'
    case '核心未确认当前 VPN 已停止': return 'The core did not confirm that the current VPN stopped.'
    case '核心未确认新配置正在运行': return 'The core did not confirm that the new configuration is running.'
    case '当前 VPN 安全停止失败': return 'Could not safely stop the current VPN.'
    case '新配置连接失败': return 'Could not connect with the new configuration.'
    case '已有 VPN 会话尚未安全停止': return 'A previous VPN session has not stopped safely.'
    case 'VPN 运行状态暂不可读，请执行安全停止': return 'VPN runtime status is unreadable. Perform a safe stop.'
    case 'VPN 运行会话已改变，拒绝写入过期状态':
      return 'The VPN session changed. An outdated runtime state was not written.'
    case 'VPN 终止状态已确认，拒绝回退到较早生命周期':
      return 'VPN termination is already confirmed. Older lifecycle state was not restored.'
    case 'VPN 升级恢复无法确认系统扩展已停止':
      return 'Upgrade recovery could not confirm that the system VPN extension stopped.'
    case 'VPN 升级恢复状态已改变，请重新检查':
      return 'VPN state changed during upgrade recovery. Check it again.'
    case '系统仍未确认旧 VPN 网络已消失，升级会话仍保持锁定':
      return 'The system has not confirmed that the previous VPN network disappeared. The upgrade session remains locked.'
    case 'VPN 授权会话状态已改变，请重新检查': return 'The VPN permission session changed. Check status again.'
    case '正在等待系统 VPN 授权': return 'Waiting for system VPN permission.'
    case '正在确认超时的 VPN 授权会话已结束': return 'Confirming that the expired VPN permission session has ended.'
    case 'VPN 扩展心跳已中断，请执行安全停止': return 'The VPN extension heartbeat stopped. Perform a safe stop.'
    case 'VPN 扩展仍在启动，请等待或执行安全停止': return 'The VPN extension is still starting. Wait or perform a safe stop.'
    case 'VPN 正在安全停止，不能再提交代理 URLTest': return 'VPN is stopping safely. A new proxy URLTest cannot start.'
    case 'VPN 正在安全停止，不能再切换节点': return 'VPN is stopping safely. Nodes cannot be switched now.'
    case '尚未选择切换节点': return 'No target node is selected.'
    case '请先连接 VPN，再切换节点': return 'Connect VPN before switching nodes.'
    case 'VPN 正在安全停止，节点切换结果已作废': return 'VPN is stopping safely. The node switch result was discarded.'
    case '代理节点切换失败': return 'Proxy node switch failed.'
    case '代理核心未返回实际选中节点': return 'The proxy core did not report the selected node.'
    case '代理节点已切换，但运行状态读回未确认': return 'The node switched, but runtime readback was not confirmed.'
    case 'VPN 连接已停止，无法完成节点切换': return 'VPN stopped before the node switch completed.'
    case '代理节点切换超时': return 'Proxy node switch timed out.'
    case '尚未选择测速节点': return 'No node is selected for testing.'
    case '请先连接 VPN，再进行代理 URLTest': return 'Connect VPN before proxy URLTest.'
    case 'VPN 正在安全停止，代理 URLTest 结果已作废': return 'VPN is stopping safely. The proxy URLTest result was discarded.'
    case 'VPN 连接已停止，无法完成代理 URLTest': return 'VPN stopped before proxy URLTest completed.'
    case '代理 URLTest 超时': return 'Proxy URLTest timed out.'
    case 'VPN 代理核心启动失败': return 'The VPN proxy core failed to start.'
    case 'VPN 授权会话已过期': return 'The VPN permission session expired.'
    case 'VPN 扩展启动心跳已中断': return 'The VPN extension startup heartbeat stopped.'
    case 'VPN 扩展已启动，但代理核心未进入运行状态':
      return 'The VPN extension started, but the proxy core did not enter the running state.'
    case '无法取得当前 VPN 会话，未执行未经确认的系统停止':
      return 'The current VPN session could not be identified. No unconfirmed system stop was attempted.'
    case '无法读取当前 VPN 会话，未执行未经确认的系统停止':
      return 'The current VPN session could not be read. No unconfirmed system stop was attempted.'
    case 'VPN 会话在授权交接时不可读，未执行未经确认的系统停止':
      return 'The VPN session became unreadable during permission handoff. No unconfirmed stop was attempted.'
    case 'VPN 停止确认属于其他会话，当前会话保持锁定':
      return 'The stop acknowledgement belongs to another session. The current session remains locked.'
    case 'VPN 恢复停止未获得系统扩展生命周期确认，会话仍保持锁定':
      return 'Recovery did not receive a system VPN extension stop acknowledgement. The session remains locked.'
    case '系统仍未确认 VPN 网络已消失，未清除运行会话':
      return 'The system did not confirm that the VPN network disappeared. The runtime session was kept.'
    case 'VPN 恢复停止期间会话已变化，未覆盖新状态':
      return 'The VPN session changed during recovery. Newer state was not overwritten.'
    case 'VPN 清理尚未确认，请再次执行安全停止': return 'VPN cleanup is not confirmed. Perform a safe stop again.'
    case 'VPN 停止命令已超时，未收到核心停止与 TUN 销毁确认；会话仍保持锁定':
      return 'VPN stop timed out without core-stop and TUN-destroy confirmation. The session remains locked.'
    case 'VPN 运行状态文件超过安全上限': return 'The VPN runtime status file exceeds its safety limit.'
    case '安全存储参数无效': return 'Secure storage parameters are invalid.'
    case '安全文件存储参数无效': return 'Secure file storage parameters are invalid.'
    case '安全存储内容超过允许上限': return 'Secure storage content exceeds its safety limit.'
    case '安全存储封装超过允许上限': return 'The secure storage envelope exceeds its safety limit.'
    case '安全存储写入后验证不一致': return 'Secure storage write verification failed.'
    case '安全存储加密验证不一致': return 'Secure storage encryption verification failed.'
    case '安全存储封装不是有效 JSON': return 'The secure storage envelope is not valid JSON.'
    case '安全存储封装版本或字段无效': return 'The secure storage envelope version or fields are invalid.'
    case '安全随机数长度无效': return 'The secure storage nonce length is invalid.'
    case '安全存储密文长度无效': return 'The secure storage ciphertext length is invalid.'
    case '安全存储 Base64 字段无效': return 'A secure storage Base64 field is invalid.'
    case '安全存储 nonce、密文或认证标签长度无效':
      return 'Secure storage nonce, ciphertext or authentication tag length is invalid.'
    case '安全存储密码更新未返回数据': return 'The secure-storage cipher update returned no data.'
    case '安全存储密码操作未返回数据': return 'The secure-storage cipher operation returned no data.'
    case '尚未生成可运行的代理配置': return 'No runnable proxy configuration has been generated.'
    case '代理配置为空': return 'The proxy configuration is empty.'
    case '代理配置超过 4 MiB 安全上限': return 'The proxy configuration exceeds the 4 MiB safety limit.'
    case '代理配置不是有效 JSON': return 'The proxy configuration is not valid JSON.'
    case '代理配置结构不完整': return 'The proxy configuration structure is incomplete.'
    case '代理配置缺少 TUN 入站': return 'The proxy configuration is missing its TUN inbound.'
    case '不能保存空代理配置': return 'An empty proxy configuration cannot be saved.'
    case '运行配置不是有效 JSON': return 'The runtime configuration is not valid JSON.'
    case '运行配置缺少 TUN 入站': return 'The runtime configuration is missing its TUN inbound.'
    case '运行配置缺少路由规则': return 'The runtime configuration is missing routing rules.'
    case '运行配置包含多个 TUN 入站': return 'The runtime configuration contains more than one TUN inbound.'
    case '运行配置缺少 TUN 地址': return 'The runtime configuration is missing a TUN address.'
    case '运行配置包含未授权的 TUN 地址': return 'The runtime configuration contains an unauthorized TUN address.'
    case '运行配置必须接管 IPv4 与 IPv6': return 'The runtime configuration must capture both IPv4 and IPv6.'
    case '正在执行用户请求的安全停止…': return 'Performing the user-requested safe stop…'
    case '原连接恢复失败': return 'Could not restore the previous connection.'
    case '只有在 VPN 已确认断开时才能清除本地敏感数据':
      return 'Local sensitive data can be cleared only after VPN is confirmed disconnected.'
    case '清除服务尚未就绪，请稍后重试': return 'The local data service is not ready. Try again shortly.'
    case '本地敏感数据已清除；外观与语言偏好已保留':
      return 'Local sensitive data cleared. Appearance and language preferences were kept.'
    case '清除未全部完成；已重新读取设备上的实际数据':
      return 'The reset was only partially completed. Actual on-device data was loaded again.'
    case '清除确认窗口打开失败': return 'Could not open the data-clear confirmation.'
    case '此功能需要先同意本机隐私摘要；当前为离线受限模式':
      return 'Agree to the on-device privacy summary before using this feature. Offline limited mode is active.'
    case '隐私选择保存失败': return 'Could not save the privacy choice.'
    case '请先安全断开 VPN，再撤回隐私同意': return 'Safely disconnect VPN before withdrawing privacy consent.'
    case '隐私同意已撤回；应用已进入离线受限模式':
      return 'Privacy consent withdrawn. The app is now in offline limited mode.'
    case '撤回确认窗口打开失败': return 'Could not open the consent-withdrawal confirmation.'
    case 'VPN 状态确认失败，未撤回隐私同意':
      return 'VPN status could not be confirmed. Privacy consent was not withdrawn.'
    default: return ''
  }
}

function dynamicEnglish(value: string, activeDnsName: string): string {
  let match: RegExpMatchArray | null = value.match(/^已恢复 (\d+) 个订阅，点击卡片可切换$/)
  if (match) return `Restored ${match[1]} subscriptions. Tap a card to switch.`
  match = value.match(/^已保存 (\d+) 个订阅；当前订阅含 (\d+) 个节点$/)
  if (match) return `Saved ${match[1]} subscriptions. The active subscription has ${match[2]} nodes.`
  match = value.match(/^更新完成：(\d+) 个节点、(\d+) 条规则$/)
  if (match) return `Update completed: ${match[1]} nodes and ${match[2]} rules.`
  match = value.match(/^已删除订阅，当前共 (\d+) 个$/)
  if (match) return `Subscription removed. ${match[1]} remain.`
  match = value.match(/^路由模式已切换为(规则|全局代理|直连)$/)
  if (match) {
    const mode: string = match[1] === '规则' ? 'Rule' : (match[1] === '全局代理' ? 'Global' : 'Direct')
    return `Routing mode changed to ${mode}.`
  }
  if (value === '已切换为手动选点') return 'Node strategy changed to Manual.'
  if (value === '已切换为自动优选') return 'Node strategy changed to Auto-select.'
  if (value === '已切换为周期故障转移') return 'Node strategy changed to Failover.'
  match = value.match(/^核心日志等级已设为 (debug|info|warn|error)$/)
  if (match) return `Core log level changed to ${match[1]}.`
  if (value === 'IPv6 已开启并接管双栈') return 'IPv6 enabled. TUN now captures both IPv4 and IPv6.'
  if (value === 'IPv6 已关闭，TUN 将接管并阻止 IPv6 泄漏') {
    return 'IPv6 proxying disabled. TUN will capture and block IPv6 to prevent leaks.'
  }
  match = value.match(/^仅 (\d+) 个所选应用进入 VPN$/)
  if (match) return `Only ${match[1]} selected apps will enter VPN.`
  match = value.match(/^应用白名单最多 (\d+) 个$/)
  if (match) return `The application allowlist is limited to ${match[1]} apps.`
  if (value.startsWith('已选择 ')) return `DNS preset selected: ${activeDnsName}.`
  if (value.startsWith('已切换到 ')) return 'Active subscription switched.'
  if (value.startsWith('正在更新 ')) return 'Updating the selected subscription…'
  if (value.includes('：正在安全停止当前 VPN/TUN…')) {
    return 'Safely stopping the current VPN/TUN before applying the change…'
  }
  let ruleLimit: RegExpMatchArray | null = value.match(/^本地规则最多 (\d+) 条$/)
  if (ruleLimit) return `Local rules are limited to ${ruleLimit[1]}.`
  if (value.includes('已保留上次可用配置')) return 'The update failed. The last working configuration was kept.'
  if (value.startsWith('运行 DNS：')) return `Active DNS: ${activeDnsName}`
  if (value.includes('使用本次默认设置')) return 'Network settings could not be loaded. Defaults are used for this session.'
  if (value.startsWith('安全锁定：')) return 'Safety lock: the proxy core is unavailable.'
  if (value.startsWith('订阅服务器返回 HTTP ')) return value.replace('订阅服务器返回', 'Subscription server returned')
  if (value.startsWith('出口检测返回 HTTP ')) return value.replace('出口检测返回', 'Egress service returned')
  if (value.includes('规则引用尚未接通的策略组')) {
    return 'This subscription references a policy group that is not connected. Use Global or Direct mode.'
  }
  if (value.startsWith('规则模式需要尚未下载的远程规则集')) {
    return 'Rule mode needs a remote rule set that is not downloaded.'
  }
  if (value.startsWith('规则模式包含尚未支持的规则')) return 'Rule mode contains an unsupported rule.'
  if (value.startsWith('规则模式引用重名策略组')) return 'Rule mode references duplicate policy-group names.'
  if (value.startsWith('规则模式引用尚未接通的策略组')) return 'Rule mode references a policy group that is not connected.'
  if (value.startsWith('订阅中没有可用的首版节点')) return 'The subscription contains no supported proxy nodes.'
  if (value.startsWith('sing-box 配置中没有首版支持的代理出站')) return 'The sing-box profile contains no supported proxy outbounds.'
  if (value.startsWith('Clash/Mihomo 配置中没有首版支持的代理节点')) return 'The Clash/Mihomo profile contains no supported proxy nodes.'
  if (value.startsWith('节点 ') || value.startsWith('Shadowsocks ') || value.startsWith('Reality ') ||
    value.startsWith('不支持的 uTLS') || value.startsWith('WebSocket ') || value.startsWith('transport ')) {
    return 'A proxy node uses missing, invalid or unsupported parameters.'
  }
  if (value.includes('失败；旧配置恢复保存失败')) return 'The change failed and the previous settings could not be restored. VPN remains disconnected.'
  if (value.includes('失败，正在恢复原连接')) return 'The change failed. Restoring the previous connection…'
  if (value.includes('已恢复原设置和原连接')) return 'The change failed. Previous settings and connection were restored.'
  if (value.includes('原设置已恢复，但 VPN 当前断开')) return 'Previous settings were restored, but VPN is disconnected.'
  if (value.includes('原连接恢复结果未知')) return 'Previous settings were restored, but connection recovery is unconfirmed.'
  if (value.includes('新配置已保存，正在重新连接')) return 'New settings saved. Reconnecting…'
  if (value.includes('VPN 已按新配置重新连接')) return 'Settings applied and VPN reconnected.'
  if (value.includes('已保存，但重新连接结果未知')) return 'Settings were saved, but reconnect status is unconfirmed.'
  if (value.includes('原设置未改变')) return 'The change could not be saved. Existing settings were not changed.'
  if (value.includes('当前连接和设置未改变')) return 'The new runtime configuration could not be generated. Current connection and settings were not changed.'
  if (value.includes('未执行：') && value.includes('设置未改变')) return 'The change was not applied. Current settings were not changed.'
  if (value.includes('配置仍保持锁定')) return 'The operation failed. Runtime settings remain locked.'
  if (value.includes('断开结果尚未确认')) return 'VPN disconnect status is not confirmed.'
  if (value.includes('请重新检查 VPN 状态')) return 'VPN status is unconfirmed. Check it again.'
  if (value.includes('代理测速完成')) return 'Node proxy test completed.'
  if (value.includes('代理测速失败')) return 'Node proxy test failed.'
  if (value.startsWith('请等待当前配置保存完成后再')) return 'Wait for the current settings save before continuing.'
  if (value.startsWith('请等待本地配置恢复完成后再')) return 'Wait for local settings to finish restoring before continuing.'
  if (value.startsWith('请先断开 VPN 再')) return 'Disconnect VPN before continuing.'
  if (value.startsWith('请等待当前 VPN 操作完成后再')) return 'Wait for the current VPN operation before continuing.'
  if (value.startsWith('请先重新检查 VPN 状态后再')) return 'Check VPN status again before continuing.'
  if (value.startsWith('请等待当前 VPN 操作或本地保存完成')) return 'Wait for the current VPN or local save operation to finish.'
  return ''
}

export function localizeRuntimeMessage(value: string, language: string, activeDnsName: string): string {
  if (!language.toLowerCase().startsWith('en')) return value
  const exact: string = exactEnglish(value)
  if (exact.length > 0) return exact
  const dynamic: string = dynamicEnglish(value, activeDnsName)
  if (dynamic.length > 0) return dynamic
  const code: string = hnaCode(value)
  if (code.length > 0) return `Runtime operation failed (${code}). Open Diagnostics for the safe error category.`
  if (hasHan(value)) return 'The operation could not be completed. Open Diagnostics for details.'
  return value
}
