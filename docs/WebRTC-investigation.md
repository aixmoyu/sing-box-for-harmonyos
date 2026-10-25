# WebRTC 实现对照与后续验证

SFA 的组测速通过运行服务的 CommandClient.urlTest 发起（参考 app/src/main/java/io/nekohasekai/sfa/compose/screen/dashboard/groups/GroupsViewModel.kt）。独立导入节点并非运行服务的已有出站，因此鸿蒙额外使用临时无入站实例。

sing-box 官方 STUN 嗅探属于 UDP 协议识别，路由动作 reject 可以放在规则／全局的宽泛直连规则之前。匹配端口不能覆盖所有自定义 STUN 端口；只屏蔽 stun.* 域名也不能覆盖缓存和字面 IP。禁用 STUN 不等于浏览器不公开本地 host 候选，更不等于系统 IPv6 路由已经被证明接管。

参考 dae 路由文档的分流规则与 DNS 分工，路由器是手机的上游网关，能在流量离开设备后接管；手机 VPN 需要另外证明系统将双栈流量交给隧道。不能把 Linux eBPF／透明网关能力视为普通鸿蒙应用已经具有的能力。

已完成的对照：严格防护关→开→关，STUN srflx IPv4 数量为2→0→2，HTTPS IPv4 出口一致。该 Wi-Fi 环境 IPv6 HTTPS 请求失败，没有复现原截图的 IPv6 条件。下一步需在有可用 IPv6 的网络，以同一自定义配置分别记录 HTTPS IPv6、host/srflx 候选和 VPN 路由生命周期；不得将无候选或 IPv6 测试失败标记为通过。

来源：
- https://github.com/SagerNet/sing-box-for-android
- https://sing-box.sagernet.org/configuration/route/sniff/
- https://sing-box.sagernet.org/configuration/route/rule_action/
- https://github.com/daeuniverse/dae/blob/main/docs/en/configuration/routing.md
